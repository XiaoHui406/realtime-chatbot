import asyncio
import concurrent.futures
from typing import AsyncGenerator

from faster_qwen3_tts import FasterQwen3TTS
from numpy import ndarray

from service.tts.interface.tts_service import TTSService


class QwenTTSService(TTSService):

    def __init__(self) -> None:
        self.ref_text = (
            "I'm confused why some people have super short timelines, yet at the same time are bullish on scaling up "
            "reinforcement learning atop LLMs. If we're actually close to a human-like learner, then this whole approach "
            "of training on verifiable outcomes is doomed."
        )
        self.ref_audio = './ref_audio.wav'
        self.language = 'Chinese'
        self.model = FasterQwen3TTS.from_pretrained(
            model_name='Qwen/Qwen3-TTS-12Hz-0.6B-Base'
        )
        self.model.generate_voice_clone(
            text='你好', language=self.language,
            ref_audio=self.ref_audio, ref_text=self.ref_text)
        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

    async def generate(
        self,
        content: str
    ) -> bytes:
        audio_list, _ = await asyncio.to_thread(
            self.model.generate_voice_clone,
            text=content, language=self.language,
            ref_audio=self.ref_audio, ref_text=self.ref_text
        )
        if not isinstance(audio_list[0], ndarray):
            raise TypeError('audio_list[0] is not ndarray')
        return audio_list[0].tobytes()

    async def generate_stream(self, content) -> AsyncGenerator[bytes, None]:
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue()

        def _produce():
            try:
                for audio_chunk, _, _ in self.model.generate_voice_clone_streaming(
                    text=content, language=self.language,
                    ref_audio=self.ref_audio, ref_text=self.ref_text,
                ):
                    chunk_bytes = audio_chunk.tobytes()
                    loop.call_soon_threadsafe(queue.put_nowait, chunk_bytes)
            except Exception as e:
                loop.call_soon_threadsafe(queue.put_nowait, e)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)  # 结束哨兵

        loop.run_in_executor(self._executor, _produce)

        while True:
            chunk_bytes = await queue.get()
            if chunk_bytes is None:
                break
            elif isinstance(chunk_bytes, Exception):
                raise chunk_bytes
            yield chunk_bytes
