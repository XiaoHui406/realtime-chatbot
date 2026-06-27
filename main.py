import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
import uuid

from fastapi import FastAPI, UploadFile, WebSocket
import numpy as np
from silero_vad import load_silero_vad, VADIterator, get_speech_timestamps
from sqlalchemy import select
import torch
from typing import Dict, List
import uvicorn
import os
import soundfile as sf

from database_engine import create_database_and_table, get_database
from model.reference_audio import ReferenceAudio, ReferenceAudioResponse
from utils.audio_utils import preprocess_audio_to_waveform
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
device = torch.device('cuda')


@asynccontextmanager
async def lifespan(app: FastAPI):
    global \
        asr_service, \
        tts_service, \
        vad_model

    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor(max_workers=3) as pool:
        f_asr = loop.run_in_executor(pool, SenseVoiceService)
        f_tts = loop.run_in_executor(pool, QwenTTSService)
        f_vad = loop.run_in_executor(pool, load_silero_vad)

        asr_service, tts_service, vad_model = await asyncio.gather(
            f_asr, f_tts, f_vad
        )

    vad_model = vad_model.to(device)  # type: ignore

    await create_database_and_table()

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
            try:
                async for audio_chunk in tts_service.generate_stream(llm_content):
                    await websocket.send_bytes(audio_chunk)
            except NotImplementedError:
                response_audio_bytes = await tts_service.generate(llm_content)
                await websocket.send_bytes(response_audio_bytes)
    except asyncio.CancelledError:
        raise


@app.post('/upload_reference_audio', response_model=str)
async def upload_reference_audio(audio: UploadFile, name: str, tags: str):
    # 定义文件名称和路径
    filename = f'{uuid.uuid4()}.wav'
    file_path = f'./audio/{filename}'
    # 音频数据存储
    buffer = np.array([], dtype=np.float32)

    if not asr_service:
        raise ValueError("asr service is none")

    try:
        # 读取音频数据
        audio_bytes = await audio.read()
        waveform = await preprocess_audio_to_waveform(audio_bytes, filename_hint=audio.filename or '')

        # 获取vad识别出的时间戳，取前3块
        timestamps = get_speech_timestamps(
            audio=torch.as_tensor(waveform, device=device), model=vad_model)[:3]
        if len(timestamps) == 0:
            raise ValueError('No human voice was detected in this audio')
        # 根据时间戳提取音频数据到buffer
        for timestamp in timestamps:
            buffer = np.concatenate(
                (buffer, waveform[timestamp['start']: timestamp['end']]))
        # 将buffer保存为文件，方便之后使用
        sf.write(file=file_path, data=buffer, samplerate=16000)
        # 使用asr识别文本
        transcribe_text = await asr_service.transcribe(buffer)
        # 信息保存到数据库
        reference_audio = ReferenceAudio(
            name=name, file_path=file_path, transcribe_text=transcribe_text, tags=tags)
        async with get_database() as database:
            database.add(reference_audio)
            await database.commit()
        return 'audio has been successfully uploaded'

    except Exception:
        try:
            await asyncio.to_thread(os.remove, file_path)
        except OSError:
            pass
        raise


@app.get('/get_reference_audios', response_model=List[ReferenceAudioResponse])
async def get_reference_audios() -> List[ReferenceAudioResponse]:
    reference_audio_list: List[ReferenceAudioResponse] = []
    async with get_database() as database:
        result = await database.execute(select(ReferenceAudio))
        reference_audios = result.scalars().all()
    for audio in reference_audios:
        reference_audio_list.append(
            ReferenceAudioResponse(
                id=audio.id, name=audio.name, tags=audio.tags
            )
        )
    return reference_audio_list


@app.get('/set_reference_audio', response_model=str)
async def set_reference_audio(audio_id: int):
    if not tts_service:
        raise ValueError('tts service is none')
    await tts_service.set_reference_audio(audio_id=audio_id)
    return 'audio has been successfully set'


@app.get('/delete_reference_audio', response_model=str)
async def delete_reference_audio(audio_id: int):
    async with get_database() as database:
        result = await database.execute(select(ReferenceAudio).filter(
            ReferenceAudio.id == audio_id
        ))
        audio = result.scalars().one_or_none()
        if not audio:
            raise ValueError(f'reference_audio.id: {audio_id} is not exist')

        try:
            await asyncio.to_thread(os.remove, audio.file_path)
        except OSError:
            pass
        await database.delete(audio)
        await database.commit()
    return 'audio has been successfully deleted'


if __name__ == "__main__":
    uvicorn.run("main:app", reload=True)
