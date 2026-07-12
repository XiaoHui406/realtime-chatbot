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
import service_registry


SAMPLE_RATE: int = 16000  # 采样率，音频每秒的采用次数
CHUNK_DURATION: float = 0.032  # 前端发送的音频时长(s)

# 16000块/秒 * 0.032秒 * 2byte/块(16bit/块) = 1024byte
# 每次发送的音频要满足16kHz采样率，16bit位深，1024byte大小
CHUNK_SIZE: int = int(SAMPLE_RATE * CHUNK_DURATION)

# 1000秒的音频数据长度，大约30MB
BUFFER_MAX_SIZE = SAMPLE_RATE * 1000

MAX_SEGMENT_GAP: float = 0.5  # 片段最大间隔(s)，如果两个片段的间隔小于该时间，则视为同一片段


device = torch.device('cuda')


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
async def realtime_chat(websocket: WebSocket, session_id: int | None = None, api_key: str = ""):
    # AUTH_API_KEY身份验证
    if AUTH_API_KEY and api_key != AUTH_API_KEY:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    # 接受连接并发送招呼语
    await websocket.accept()
    await websocket.send_json({"msg": "welcome to connect"})

    # 给chatbot_service设置session_id，并从数据库中获取对应session的对话上下文
    if session_id is not None:
        await service_registry.chatbot_service.set_session(session_id)

    # 给client_request_manager设置websocket连接
    # 方便大模型调用需要向客户端发送请求的tool(如get_location)时能通过websocket发送
    service_registry.client_request_manager.set_websocket(websocket)

    buffer = np.array([], dtype=np.float32)  # 存储收到的音频数据
    buffer_offset = 0  # 跟踪 buffer 的起始偏移量

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
    vad_iter = VADIterator(model=service_registry.vad_model)

    # 存放VAD识别出的时间戳(实际为buffer的索引，数值上等于SAMPLE_RATE * 时间戳)
    # start和end共同指出一个音频片段
    timestamp_start: int | float | None = None
    timestamp_end: int | float | None = None

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
            # print(f'{len(buffer)=}')

            # 识别时间戳，识别出的timestamp有三种情况
            # 1. {'start': xxx}，识别出了音频片段的开头
            # 2. {'end': xxx}，识别出了音频片段的结尾
            # 3. None，未识别出时间戳
            timestamp: Dict[str, float | int] | None = vad_iter(
                x=torch.as_tensor(data=waveform, device=device)
            )  # {'start': xxx}, {'end': xxx}
            if timestamp:
                # 如果时间戳的key为start，说明检测出了一个片段的开头
                if "start" in timestamp:
                    # 如果此时timestamp_start和timestamp_end都不是None
                    # 代表之前检测到一个片段，但和当前片段的时间差不超过MAX_SEGMENT_GAP
                    # 因此将两个片段视为同一个，将上一个片段的timestamp_end置为None
                    if timestamp_start and timestamp_end:
                        if (timestamp['start'] - timestamp_end) / SAMPLE_RATE <= MAX_SEGMENT_GAP:
                            timestamp_end = None
                    else:
                        # 转换为相对于当前 buffer 的索引
                        timestamp_start = timestamp["start"] - buffer_offset
                        # print(f'{timestamp_start=}')
                # 如果时间戳的key为start，说明检测出了一个片段的末尾
                elif "end" in timestamp:
                    timestamp_end = timestamp["end"] - buffer_offset
            else:
                # 如果没有时间戳(timestamp is None)
                # 检查timestamp_start和timestamp_end是否为None
                if timestamp_start and timestamp_end:
                    # 如果时间差超过MAX_SEGMENT_GAP，将片段发送给asr_worker
                    if (len(buffer) - timestamp_end) / SAMPLE_RATE > MAX_SEGMENT_GAP:
                        chunk = buffer[timestamp_start:timestamp_end]
                        await audio_queue.put(chunk)
                        if len(buffer) > BUFFER_MAX_SIZE:
                            buffer = buffer[timestamp_end:]
                            buffer_offset += timestamp_end  # 更新偏移量
                            vad_iter.reset_states()
                        timestamp_start, timestamp_end = None, None
    except Exception as e:
        print(f"Main loop error: {e}")
    finally:
        service_registry.client_request_manager.cancel_all()
        service_registry.client_request_manager.set_websocket(None)
        asr_task.cancel()
        try:
            await asr_task
        except asyncio.CancelledError:
            pass


async def asr_worker(audio_queue: asyncio.Queue, asr_content_queue: asyncio.Queue[str]):
    """后台任务：从队列中获取音频片段，执行转写并发送结果"""
    if not service_registry.asr_service:
        raise ValueError("asr service is none")

    while True:
        try:
            audio = await audio_queue.get()
            asr_result = await service_registry.asr_service.transcribe(audio)
            print(f'{asr_result=}')
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


async def chatbot_worker(asr_content_queue: asyncio.Queue[str], llm_content_queue: asyncio.Queue[str]):
    while True:
        try:
            asr_content: str = await asr_content_queue.get()
            response_content = ""
            async for content in service_registry.chatbot_service.chat([
                ChatCompletionContentPartTextParam(
                    type='text', text=asr_content)
            ]):
                response_content += content.strip()
                for char in separate_char_list:
                    index = response_content.rfind(char)
                    # 发现分隔符
                    if index != -1:
                        # 句子过短，可能使生成的音频质量差，故跳过处理并继续循环
                        if index <= 5:
                            continue
                        # 如果分隔符是content的最后一个字符
                        # 把response_content放入队列，并置空
                        elif index == len(content) - 1:
                            await llm_content_queue.put(response_content)
                            response_content = ''
                        # 如果分隔符不是content的最后一个字符
                        # 取response_content到分隔符为止的字符串（包括分隔符）放入队列
                        # 把response_content赋值为分隔符到末尾（不包括分隔符）的字符串
                        else:
                            await llm_content_queue.put(response_content[:index + 1])
                            response_content = response_content[index + 1:]
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
            try:
                async for audio_chunk in service_registry.tts_service.generate_stream(llm_content):
                    await websocket.send_bytes(audio_chunk)
            except NotImplementedError:
                response_audio_bytes = await service_registry.tts_service.generate(llm_content)
                await websocket.send_bytes(response_audio_bytes)
    except asyncio.CancelledError:
        raise


if __name__ == "__main__":
    uvicorn.run("main:app", reload=True)
