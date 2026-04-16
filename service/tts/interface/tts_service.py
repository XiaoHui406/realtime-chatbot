from abc import ABC, abstractmethod

from numpy import ndarray


class TTSService(ABC):

    @abstractmethod
    async def generate(self, content: str) -> bytes:
        ...
