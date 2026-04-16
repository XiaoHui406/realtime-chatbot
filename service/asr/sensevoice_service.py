import asyncio
from typing import Any

import funasr
from numpy import ndarray
from funasr.utils.postprocess_utils import rich_transcription_postprocess
from service.asr.interface.asr_service import ASRService


class SenseVoiceService(ASRService):
    def __init__(self) -> None:
        self.model = funasr.AutoModel(
            model='iic/SenseVoiceSmall',
            device='cuda:0'
        )

    async def transcribe(self, chunk: ndarray) -> str:
        asr_result = await asyncio.to_thread(
            self.model.generate,
            input=chunk,
            language='zh',
            use_itn=False,
            ban_emo_unk=True
        )
        return rich_transcription_postprocess(asr_result[0]["text"])
