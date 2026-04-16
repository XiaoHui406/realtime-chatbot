import asyncio
from typing import Any, List
from faster_whisper import WhisperModel
from numpy import ndarray

from service.asr.interface.asr_service import ASRService


class WhisperService(ASRService):
    def __init__(self) -> None:
        self.model = WhisperModel('small')

    async def transcribe(
        self,
        chunk: ndarray
    ) -> str:
        words: List[str] = []
        segments, _ = await asyncio.to_thread(
            self.model.transcribe,
            audio=chunk,
            initial_prompt='以下是简体中文的句子。',
            language='zh',
            vad_filter=True
        )
        for segment in segments:
            words.append(segment.text)
        return ''.join(words)
