import asyncio
import json
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse
import numpy as np
from silero_vad import VADIterator
import torch
from typing import Dict, List
import uvicorn
from openai.types.chat.chat_completion_content_part_text_param import ChatCompletionContentPartTextParam

from database_engine import create_database_and_table
from router.chatbot_session_router import chatbot_session_router
from router.reference_audio_router import reference_audio_router
from service.chatbot.interface.chatbot_service import ChatbotService
from service.chatbot.llm_api_service import LLMAPIService
from utils.tool_call.tool_manager_registry import init_tool_manager
from utils.auth import AUTH_API_KEY
from utils.latency_tracer import tracer
from utils.text_sanitizer import sanitize_for_tts
import service_registry


SAMPLE_RATE: int = 16000  # 采样率，音频每秒的采用次数
CHUNK_DURATION: float = 0.032  # 前端发送的音频时长(s)

# 16000块/秒 * 0.032秒 * 2byte/块(16bit/块) = 1024byte
# 每次发送的音频要满足16kHz采样率，16bit位深，1024byte大小
CHUNK_SIZE: int = int(SAMPLE_RATE * CHUNK_DURATION)

# 端点静音时长(ms)：静音持续超过该时长，VAD才发出end事件认为一句话结束
# 其间的短停顿由VAD内部自动合并进同一片段
MIN_SILENCE_DURATION_MS: int = 200

# 空闲buffer上限：无语音活动时buffer超过此长度则裁剪，防止静音连接导致的无限增长
IDLE_BUFFER_MAX_S = 30  # 30秒静音
IDLE_BUFFER_KEEP_S = 5  # 裁剪时保留最近5秒


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 初始化各个service
    await service_registry.init_service()
    # 当数据库和表未创建时执行创建
    await create_database_and_table()
    # 初始化tool_manager，方便大模型调用tool
    await init_tool_manager()

    yield


app = FastAPI(lifespan=lifespan)


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    # 如果AUTH_API_KEY为None，则跳过验证
    if not AUTH_API_KEY:
        return await call_next(request)

    # websocket请求在请求内自行做验证
    if request.url.path == "/realtime-chat":
        return await call_next(request)

    # 获取headers中的Authorization，如果不是AUTH_API_KEY，返回401
    auth_header = request.headers.get("Authorization", "")
    if auth_header != f"Bearer {AUTH_API_KEY}":
        return JSONResponse(status_code=401, content={"detail": "Invalid or missing API key"})

    return await call_next(request)


app.include_router(reference_audio_router)
app.include_router(chatbot_session_router)


@app.websocket("/realtime-chat")
async def realtime_chat(websocket: WebSocket, session_id: int | None = None):
    # AUTH_API_KEY身份验证：与REST接口一致，从Authorization header读取
    # 不使用查询参数传递，避免key进入访问日志
    if AUTH_API_KEY:
        auth_header = websocket.headers.get("authorization", "")
        if auth_header != f"Bearer {AUTH_API_KEY}":
            await websocket.close(code=4001, reason="Unauthorized")
            return

    # 接受连接并发送招呼语
    await websocket.accept()
    await websocket.send_json({"msg": "welcome to connect"})

    # 预热LLM连接(TCP+TLS握手)，降低本次通话首轮对话的TTFT
    # fire-and-forget，不阻塞连接建立
    warmup_task = asyncio.create_task(
        service_registry.chatbot_service.warmup())

    # 给chatbot_service设置session_id，并从数据库中获取对应session的对话上下文
    if session_id is not None:
        await service_registry.chatbot_service.set_session(session_id)

    # 给client_request_manager设置websocket连接
    # 方便大模型调用需要向客户端发送请求的tool(如get_location)时能通过websocket发送
    service_registry.client_request_manager.set_websocket(websocket)

    buffer = np.array([], dtype=np.float32)  # 存储收到的音频数据
    # buffer[0]在VAD绝对采样坐标系中的索引（即累计被裁剪掉的样本数）
    # 不变量：buffer_offset + len(buffer) == VAD已处理的总样本数
    buffer_offset = 0

    # 存放VAD识别出的音频片段数据
    audio_queue = asyncio.Queue()
    # 存放ASR从音频中识别出的文字
    asr_content_queue: asyncio.Queue[str] = asyncio.Queue()
    # 存放LLM输出的回复，按separate_char_list切分
    llm_content_queue: asyncio.Queue[str] = asyncio.Queue()

    # 创建各个任务
    asr_task = asyncio.create_task(asr_worker(audio_queue, asr_content_queue))
    chatbot_task = asyncio.create_task(
        chatbot_worker(asr_content_queue, llm_content_queue))
    tts_task = asyncio.create_task(tts_worker(websocket, llm_content_queue))
    # 创建VAD迭代器
    vad_iter = VADIterator(
        model=service_registry.vad_model,
        min_silence_duration_ms=MIN_SILENCE_DURATION_MS,
    )

    # 存放VAD识别出的片段起点(VAD绝对采样索引，数值上等于SAMPLE_RATE * 时间戳)
    # VAD全程连续计数不重置，取片段时通过buffer_offset换算为buffer索引
    timestamp_start: int | float | None = None

    try:
        while True:
            # 获取客户端发送的数据
            receive_data = await websocket.receive()
            # 数据类型为text，该情况下有两种可能
            # 一是收到exit，客户端主动断开连接
            # 二是收到client_request_manager向客户端发起请求的返回数据
            if "text" in receive_data:
                if receive_data["text"] == "exit":
                    break
                else:
                    try:
                        data: Dict = json.loads(receive_data["text"])
                        if data.get("type") == "response":
                            # 获取返回结果
                            service_registry.client_request_manager.handle_response(
                                data["request_id"], data["result"])
                    except (json.JSONDecodeError, KeyError, TypeError):
                        pass
                    continue
            # 收到二进制数据，为客户端发送的音频数据
            elif "bytes" in receive_data:
                # 音频数据转为numpy数组
                audio_bytes = np.frombuffer(
                    receive_data["bytes"], dtype=np.int16)
                # 由int16转为float32，用于之后的VAD和ASR推理
                waveform = audio_bytes.astype(np.float32) / 32768.0
            else:
                continue

            # 音频数据存入buffer
            buffer = np.concatenate((buffer, waveform))

            # 静音连接保护：无语音活动时buffer超过上限则裁剪，保留最近几秒
            if timestamp_start is None and len(buffer) > IDLE_BUFFER_MAX_S * SAMPLE_RATE:
                trim_at = len(buffer) - IDLE_BUFFER_KEEP_S * SAMPLE_RATE
                buffer = buffer[trim_at:]
                buffer_offset += trim_at

            # 识别时间戳，识别出的timestamp有三种情况
            # 1. {'start': xxx}，识别出了音频片段的开头
            # 2. {'end': xxx}，识别出了音频片段的结尾(静音已持续MIN_SILENCE_DURATION_MS)
            # 3. None，未识别出时间戳
            timestamp: Dict[str, float | int] | None = vad_iter(
                x=torch.as_tensor(data=waveform)
            )  # {'start': xxx}, {'end': xxx}
            if timestamp:
                # 检测出片段开头，记录起点
                if "start" in timestamp:
                    timestamp_start = timestamp["start"]
                # 检测出片段结尾，立即切分并送入ASR
                # 短停顿的合并已由VAD内部完成，end事件发出即代表一句话结束
                elif "end" in timestamp and timestamp_start is not None:
                    # 打点：VAD检测到语音结束，作为本轮延迟统计的基准点
                    tracer.start_turn()
                    # 绝对坐标换算为buffer索引后取出片段
                    cut = timestamp["end"] - buffer_offset
                    chunk = buffer[timestamp_start - buffer_offset:cut]
                    # 打点：片段送入ASR队列
                    tracer.mark("segment_queued")
                    await audio_queue.put(chunk)
                    # 每次切分后立即裁剪buffer，避免buffer无限增长导致concat开销恶化
                    buffer = buffer[cut:]
                    buffer_offset += cut
                    timestamp_start = None
    finally:
        service_registry.client_request_manager.cancel_all()
        service_registry.client_request_manager.set_websocket(None)
        # 取消所有后台任务并等待其退出
        # 若不清理，连接断开后悬挂的任务失去强引用，会在GC时
        # 报"Task was destroyed but it is pending!"
        tasks = (warmup_task, asr_task, chatbot_task, tts_task)
        for task in tasks:
            task.cancel()
        # return_exceptions=True会一并取回各任务的异常(含CancelledError)
        # 避免产生"Task exception was never retrieved"告警
        await asyncio.gather(*tasks, return_exceptions=True)


async def asr_worker(audio_queue: asyncio.Queue, asr_content_queue: asyncio.Queue[str]):
    """后台任务：从队列中获取音频片段，执行转写并发送结果"""
    if not service_registry.asr_service:
        raise ValueError("asr service is none")

    while True:
        try:
            audio = await audio_queue.get()
            asr_result = await service_registry.asr_service.transcribe(audio)
            # 打点：ASR转写完成
            tracer.mark("asr_done")
            await asr_content_queue.put(asr_result)
        except asyncio.CancelledError:
            raise


separate_char_list: List[str] = [
    ".",
    "。",
    "\n",
    "?",
    "!",
    "？",
    "！",
]

# 首句额外允许的分隔符（逗号等）
# 首句用更激进的切分让TTS尽早启动，后续句子恢复正常切分以保证语音自然度
first_sentence_extra_char_list: List[str] = [
    "，",
    ",",
    "、",
    "；",
    ";",
    "：",
    ":",
]


async def chatbot_worker(asr_content_queue: asyncio.Queue[str], llm_content_queue: asyncio.Queue[str]):
    while True:
        try:
            asr_content: str = await asr_content_queue.get()
            response_content = ""
            # 本轮回复是否已切出首句
            first_sentence_sent = False
            async for content in service_registry.chatbot_service.chat([
                ChatCompletionContentPartTextParam(
                    type='text', text=asr_content)
            ]):
                # 打点：收到LLM的首个内容token（TTFT）
                tracer.mark("llm_first_token", first_only=True)
                response_content += content.strip()
                # 首句允许额外用逗号等切分，让TTS尽早启动
                char_list = separate_char_list if first_sentence_sent \
                    else separate_char_list + first_sentence_extra_char_list
                for char in char_list:
                    index = response_content.rfind(char)
                    # 发现分隔符
                    if index != -1:
                        # 句子过短，可能使生成的音频质量差，故跳过处理并继续循环
                        if index <= 5:
                            continue
                        # 如果分隔符是content的最后一个字符
                        # 把response_content放入队列，并置空
                        elif index == len(content) - 1:
                            # 打点：首个完整句子送入TTS队列
                            tracer.mark("first_sentence_queued",
                                        first_only=True)
                            await llm_content_queue.put(response_content)
                            response_content = ''
                        # 如果分隔符不是content的最后一个字符
                        # 取response_content到分隔符为止的字符串（包括分隔符）放入队列
                        # 把response_content赋值为分隔符到末尾（不包括分隔符）的字符串
                        else:
                            # 打点：首个完整句子送入TTS队列
                            tracer.mark("first_sentence_queued",
                                        first_only=True)
                            await llm_content_queue.put(response_content[:index + 1])
                            response_content = response_content[index + 1:]
                        first_sentence_sent = True
                        # 发现分隔符后，处理完就停止循环
                        break
            # 当大模型回复结束，但response_content不为空时(比如最后一句话没有以分隔符结尾)
            # 将response_content放入队列，此时循环结束
            if len(response_content) > 0:
                await llm_content_queue.put(response_content)
        except asyncio.CancelledError:
            raise


async def tts_worker(websocket: WebSocket, llm_content_queue: asyncio.Queue[str]):
    if not service_registry.tts_service:
        raise ValueError("tts service is none")
    try:
        while True:
            llm_content: str = await llm_content_queue.get()
            # 送入TTS前清理markdown标记，避免朗读出星号、列表序号等符号
            # (此时句子是完整文本，跨delta的成对标记在这里能被正确匹配)
            llm_content = sanitize_for_tts(llm_content)
            if not llm_content:
                continue
            # 打点：TTS开始处理首个句子
            tracer.mark("tts_start", first_only=True)
            try:
                async for audio_chunk in service_registry.tts_service.generate_stream(llm_content):
                    await websocket.send_bytes(audio_chunk)
                    # 打点：首个TTS音频块已发送给客户端
                    tracer.mark("tts_first_chunk_sent", first_only=True)
            except NotImplementedError:
                response_audio_bytes = await service_registry.tts_service.generate(llm_content)
                await websocket.send_bytes(response_audio_bytes)
                # 打点：首个TTS音频块已发送给客户端
                tracer.mark("tts_first_chunk_sent", first_only=True)
    except asyncio.CancelledError:
        raise


if __name__ == "__main__":
    uvicorn.run("main:app", reload=True, reload_excludes=["app/*"])
