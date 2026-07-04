import uuid
import torch
import numpy as np
import soundfile as sf
import os
import asyncio

from fastapi import APIRouter, UploadFile
from silero_vad import get_speech_timestamps
from typing import List
from sqlalchemy import select

import service_registry
from utils.audio_utils import preprocess_audio_to_waveform
from database_engine import get_database
from model.reference_audio import ReferenceAudio, ReferenceAudioResponse


reference_audio_router = APIRouter(
    prefix='/reference_audio',
    tags=['reference audio']
)


@reference_audio_router.post('', response_model=str)
async def upload_reference_audio(audio: UploadFile, name: str, tags: str):
    # 定义文件名称和路径
    filename = f'{uuid.uuid4()}.wav'
    file_path = f'./audio/{filename}'
    # 音频数据存储
    buffer = np.array([], dtype=np.float32)

    if not service_registry.asr_service:
        raise ValueError("asr service is none")

    try:
        # 读取音频数据
        audio_bytes = await audio.read()
        waveform = await preprocess_audio_to_waveform(audio_bytes, filename_hint=audio.filename or '')

        # 获取vad识别出的时间戳，取前3块
        timestamps = get_speech_timestamps(
            audio=torch.as_tensor(waveform, device='cuda'), model=service_registry.vad_model)[:3]
        if len(timestamps) == 0:
            raise ValueError('No human voice was detected in this audio')
        # 根据时间戳提取音频数据到buffer
        for timestamp in timestamps:
            buffer = np.concatenate(
                (buffer, waveform[timestamp['start']: timestamp['end']]))
        # 将buffer保存为文件，方便之后使用
        sf.write(file=file_path, data=buffer, samplerate=16000)
        # 使用asr识别文本
        transcribe_text = await service_registry.asr_service.transcribe(buffer)
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


@reference_audio_router.get('', response_model=List[ReferenceAudioResponse])
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


@reference_audio_router.put('/{audio_id}/activate', response_model=str)
async def set_reference_audio(audio_id: int):
    if not service_registry.tts_service:
        raise ValueError('tts service is none')
    await service_registry.tts_service.set_reference_audio(audio_id=audio_id)
    return 'audio has been successfully set'


@reference_audio_router.put('/{audio_id}', response_model=str)
async def edit_reference_audio(audio_id: int, name: str, tags: str):
    async with get_database() as database:
        result = await database.execute(select(ReferenceAudio).filter(
            ReferenceAudio.id == audio_id
        ))
        audio = result.scalars().one_or_none()
        if not audio:
            raise ValueError(f'reference_audio.id: {audio_id} is not exist')
        audio.name = name
        audio.tags = tags
        await database.commit()
    return 'audio has been successfully edited'


@reference_audio_router.delete('/{audio_id}', response_model=str)
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
