import asyncio
from typing import Any

import funasr
from numpy import ndarray
from funasr.utils.postprocess_utils import rich_transcription_postprocess
import torch
from service.asr.interface.asr_service import ASRService


class SenseVoiceService(ASRService):
    def __init__(self) -> None:
        try:
            self.model = funasr.AutoModel(
                model='iic/SenseVoiceSmall',
                device='cuda:0'
            )
        except NotImplementedError:
            self.model = funasr.AutoModel(
                model='iic/SenseVoiceSmall',
                device='cpu'
            )
            device = torch.device('cuda:0')
            self.model.model.to(device)
            self.model.kwargs['device'] = 'cuda:0'  # type: ignore
            self.model._base_kwargs_map['kwargs']['device'] = 'cuda:0'

    async def transcribe(self, chunk: ndarray) -> str:
        asr_result = await asyncio.to_thread(
            self.model.generate,
            input=chunk,
            language='zh',
            use_itn=False,
            ban_emo_unk=True
        )
        return rich_transcription_postprocess(asr_result[0]["text"])
