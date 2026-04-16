from abc import ABC, abstractmethod

from numpy import ndarray


class ASRService(ABC):

    @abstractmethod
    async def transcribe(
        self,
        chunk: ndarray
    ) -> str:
        ...
