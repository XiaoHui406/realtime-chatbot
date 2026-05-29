import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket
import numpy as np
from silero_vad import load_silero_vad, VADIterator
import torch
from typing import Dict, List
import uvicorn

from service.asr.sensevoice_service import SenseVoiceService
from service.asr.whisper_service import WhisperService
from service.asr.interface.asr_service import ASRService
from service.chatbot.interface.chatbot_service import ChatbotService
from service.chatbot.llm_api_service import LLMAPIService
from service.tts.interface.tts_service import TTSService
from service.tts.qwen_tts_service import QwenTTSService


SAMPLE_RATE: int = 16000
CHUNK_DURATION: float = 0.032  # 前端发送的音频时长(s)
CHUNK_SIZE: int = int(SAMPLE_RATE * CHUNK_DURATION)
BUFFER_MAX_SIZE = CHUNK_SIZE * 1000

MAX_SEGMENT_GAP: float = 0.5  # 片段最大间隔(s)，如果两个片段的间隔小于该时间，则视为同一片段


asr_service: ASRService | None = None
tts_service: TTSService | None = None
vad_model = None
device = None
api_key: str | None = None
base_url: str | None = None
llm_model: str | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global \
        asr_service, \
        tts_service, \
        vad_model, \
        device, \
        api_key, \
        base_url, \
        llm_model

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor(max_workers=3) as pool:
        f_asr = loop.run_in_executor(pool, SenseVoiceService)
        f_tts = loop.run_in_executor(pool, QwenTTSService)
        f_vad = loop.run_in_executor(pool, load_silero_vad)

        asr_service, tts_service, vad_model = await asyncio.gather(
            f_asr, f_tts, f_vad
        )

    vad_model = vad_model.to(device)  # type: ignore

    yield


app = FastAPI(lifespan=lifespan)


@app.websocket("/realtime-chat")
async def realtime_chat(websocket: WebSocket):
    await websocket.accept()
    await websocket.send_json({"msg": "welcome to connect"})
    buffer = np.array([], dtype=np.float32)
    buffer_offset = 0  # 跟踪 buffer 的起始偏移量

    audio_queue = asyncio.Queue()
    asr_content_queue: asyncio.Queue[str] = asyncio.Queue()
    llm_content_queue: asyncio.Queue[str] = asyncio.Queue()
    asr_task = asyncio.create_task(asr_worker(audio_queue, asr_content_queue))
    chatbot_task = asyncio.create_task(
        chatbot_worker(asr_content_queue, llm_content_queue))
    tts_task = asyncio.create_task(tts_worker(websocket, llm_content_queue))
    vad_iter = VADIterator(model=vad_model)

    timestamp_start: int | float | None = None
    timestamp_end: int | float | None = None

    try:
        while True:
            receive_data = await websocket.receive()
            if "text" in receive_data:
                if receive_data["text"] == "exit":
                    break
                else:
                    continue
            elif "bytes" in receive_data:
                audio_bytes = np.frombuffer(
                    receive_data["bytes"], dtype=np.int16)
                waveform = audio_bytes.astype(np.float32) / 32768.0
            else:
                continue

            buffer = np.concatenate((buffer, waveform))
            # print(f'{len(buffer)=}')

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
        asr_task.cancel()
        try:
            await asr_task
        except asyncio.CancelledError:
            pass


async def asr_worker(audio_queue: asyncio.Queue, asr_content_queue: asyncio.Queue[str]):
    """后台任务：从队列中获取音频片段，执行转写并发送结果"""
    if not asr_service:
        raise ValueError("asr service is none")

    while True:
        try:
            audio = await audio_queue.get()
            asr_result = await asr_service.transcribe(audio)
            print(f'{asr_result=}')
            await asr_content_queue.put(asr_result)
        except asyncio.CancelledError:
            raise


separate_char_list: List[str] = [
    ",",
    ".",
    "。",
    "，",
    ";",
    " ",
    "\n",
    "?",
    "!",
    "；",
    "？",
    "！",
]


async def chatbot_worker(asr_content_queue: asyncio.Queue[str], llm_content_queue: asyncio.Queue[str]):
    chatbot_service: ChatbotService = LLMAPIService()

    while True:
        try:
            asr_content: str = await asr_content_queue.get()
            response_content = ""
            async for content in chatbot_service.chat(asr_content):
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
    if not tts_service:
        raise ValueError("tts service is none")
    try:
        while True:
            llm_content: str = await llm_content_queue.get()
            response_audio_bytes = await tts_service.generate(llm_content)
            # print('发送音频数据')
            await websocket.send_bytes(response_audio_bytes)
    except asyncio.CancelledError:
        raise


if __name__ == "__main__":
    uvicorn.run("main:app", reload=True)
