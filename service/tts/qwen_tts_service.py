import asyncio
import concurrent.futures
from typing import AsyncGenerator

from faster_qwen3_tts import FasterQwen3TTS
from numpy import ndarray
from sqlalchemy import select

from database_engine import get_database
from model.reference_audio import ReferenceAudio
from service.tts.interface.tts_service import TTSService


class QwenTTSService(TTSService):

    def __init__(self, model: FasterQwen3TTS | None = None) -> None:
        self.ref_text = (
            "I'm confused why some people have super short timelines, yet at the same time are bullish on scaling up "
            "reinforcement learning atop LLMs. If we're actually close to a human-like learner, then this whole approach "
            "of training on verifiable outcomes is doomed."
        )
        self.ref_audio = './ref_audio.wav'
        self.language = 'Chinese'
        if model:
            self.model = model
        else:
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
                    chunk_size=3
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

    async def set_reference_audio(self, audio_id: int) -> None:
        async with get_database() as database:
            result = await database.execute(select(ReferenceAudio).filter(ReferenceAudio.id == audio_id))
            audio = result.scalars().one_or_none()
        if not audio:
            raise ValueError(f'reference_audio.id: {audio_id} is not exist')
        self.ref_audio, self.ref_text = audio.file_path, audio.transcribe_text
        # 执行一次空推理
        try:
            async for _ in self.generate_stream('你好'):
                pass
        except NotImplementedError:
            await self.generate('你好')
