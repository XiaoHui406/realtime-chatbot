from abc import ABC, abstractmethod
from typing import AsyncGenerator, List

from numpy import ndarray

from model.reference_audio import ReferenceAudio


class TTSService(ABC):

    @abstractmethod
    async def generate(self, content: str) -> bytes:
        ...

    # 选择性实现，如果不实现就raise NotImplementedError
    @abstractmethod
    def generate_stream(self, content) -> AsyncGenerator[bytes, None]:
        ...

    @abstractmethod
    async def set_reference_audio(self, audio_id: int) -> None:
        ...
