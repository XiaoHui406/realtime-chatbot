from abc import ABC, abstractmethod
from typing import AsyncGenerator

from numpy import ndarray


class TTSService(ABC):

    @abstractmethod
    async def generate(self, content: str) -> bytes:
        ...

    # 选择性实现，如果不实现就raise NotImplementedError
    @abstractmethod
    def generate_stream(self, content) -> AsyncGenerator[bytes, None]:
        ...
