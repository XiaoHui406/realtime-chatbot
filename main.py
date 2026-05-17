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
from service.chatbot.llm_api_service import LLMApiService
from service.tts.interface.tts_service import TTSService
from service.tts.qwen_tts_service import QwenTTSService


SAMPLE_RATE: int = 16000
CHUNK_DURATION: float = 0.032
CHUNK_SIZE: int = int(SAMPLE_RATE * CHUNK_DURATION)
BUFFER_MAX_SIZE = CHUNK_SIZE * 1000


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
    asr_task = asyncio.create_task(asr_worker(websocket, audio_queue))
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
                x=torch.Tensor(waveform).to(device)
            )
            if timestamp:
                if "start" in timestamp:
                    # 转换为相对于当前 buffer 的索引
                    timestamp_start = timestamp["start"] - buffer_offset
                    # print(f'{timestamp_start=}')
                elif "end" in timestamp:
                    timestamp_end = timestamp["end"] - buffer_offset
                    # print(f'{timestamp_end=}')
                    if timestamp_start and timestamp_end > timestamp_start:
                        chunk = buffer[timestamp_start:timestamp_end]
                        await audio_queue.put(chunk)
                        if len(buffer) > BUFFER_MAX_SIZE:
                            buffer = buffer[timestamp_end:]
                            buffer_offset += timestamp_end  # 更新偏移量
                            vad_iter.reset_states()
                        timestamp_start, timestamp_end = None, None
                else:
                    continue
            else:
                continue
    except Exception as e:
        print(f"Main loop error: {e}")
    finally:
        asr_task.cancel()
        try:
            await asr_task
        except asyncio.CancelledError:
            pass


async def asr_worker(websocket: WebSocket, audio_queue: asyncio.Queue):
    """后台任务：从队列中获取音频片段，执行转写并发送结果"""
    if not asr_service:
        raise ValueError("asr service is none")
    asr_content_queue = asyncio.Queue()
    chatbot_task = asyncio.create_task(
        chatbot_worker(websocket, asr_content_queue))

    while True:
        try:
            audio = await audio_queue.get()
            asr_result = await asr_service.transcribe(audio)
            # print(f'{asr_result=}')
            await asr_content_queue.put(asr_result)
        except asyncio.CancelledError:
            chatbot_task.cancel()
            try:
                await chatbot_task
            except asyncio.CancelledError:
                pass
            break
        except Exception as e:
            print(f"ASR worker error: {e}")


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


async def chatbot_worker(websocket: WebSocket, asr_content_queue: asyncio.Queue[str]):
    chatbot_service: ChatbotService = LLMApiService()

    llm_content_queue = asyncio.Queue()
    tts_task = asyncio.create_task(tts_worker(websocket, llm_content_queue))

    while True:
        try:
            asr_content: str = await asr_content_queue.get()
            response_content = ""
            async for content in chatbot_service.chat(asr_content):
                # print(f'{content=}')
                content = content.strip()
                response_content += content
                if len(response_content) <= 5:
                    continue
                for char in separate_char_list:
                    index = content.find(char)
                    # 发现分隔符
                    if index != -1:
                        # 如果分隔符是content的最后一个字符
                        # 把response_content放入队列，并置空
                        if index == len(content) - 1:
                            await llm_content_queue.put(response_content)
                            response_content = ''
                        # 如果分隔符不是content的最后一个字符
                        # 取response_content到分隔符为止的字符串（包括分隔符）放入队列
                        # 把response_content赋值为分隔符到末尾的字符串
                        else:
                            await llm_content_queue.put(response_content[:len(
                                response_content) - len(content) + index + 1])
                            response_content = response_content[len(
                                response_content) - len(content) + index + 1:]
                        # 发现分隔符后，处理完就停止循环
                        break
        except asyncio.CancelledError:
            tts_task.cancel()
            try:
                await tts_task
            except asyncio.CancelledError:
                pass
            break


async def tts_worker(websocket: WebSocket, llm_content_queue: asyncio.Queue[str]):
    if not tts_service:
        raise ValueError("tts service is none")
    try:
        while True:
            llm_content: str = await llm_content_queue.get()
            response_audio_bytes = await tts_service.generate(llm_content)
            # print('发送音频数据')
            await websocket.send_bytes(response_audio_bytes)
    except asyncio.CancelledError as e:
        raise asyncio.CancelledError(f"tts worker error: {e}")


if __name__ == "__main__":
    uvicorn.run("main:app", reload=True)
