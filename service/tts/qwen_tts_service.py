import asyncio
from typing import AsyncGenerator

from faster_qwen3_tts import FasterQwen3TTS
from numpy import ndarray

from service.tts.interface.tts_service import TTSService


ref_text = (
    "I'm confused why some people have super short timelines, yet at the same time are bullish on scaling up "
    "reinforcement learning atop LLMs. If we're actually close to a human-like learner, then this whole approach "
    "of training on verifiable outcomes is doomed."
)
language = 'Chinese'


class QwenTTSService(TTSService):

    def __init__(self) -> None:
        self.model = FasterQwen3TTS.from_pretrained(
            model_name='Qwen/Qwen3-TTS-12Hz-0.6B-Base'
        )
        self.model.generate_voice_clone(
            text='你好', language=language,
            ref_audio='audio/ref_audio.wav', ref_text=ref_text)

    async def generate(
        self,
        content: str
    ) -> bytes:
        audio_list, _ = await asyncio.to_thread(
            self.model.generate_voice_clone,
            text=content, language=language,
            ref_audio='audio/ref_audio.wav', ref_text=ref_text
        )
        if not isinstance(audio_list[0], ndarray):
            raise TypeError('audio_list[0] is not ndarray')
        return audio_list[0].tobytes()

    async def generate_stream(self, content) -> AsyncGenerator[bytes, None]:
        for audio_chunk, _, _ in await asyncio.to_thread(
            self.model.generate_voice_clone_streaming,
            text=content, language=language,
            ref_audio='audio/ref_audio.wav', ref_text=ref_text
        ):
            yield audio_chunk.tobytes()
