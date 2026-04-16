from abc import ABC, abstractmethod
from typing import AsyncGenerator


class ChatbotService(ABC):

    @abstractmethod
    def chat(self, message: str) -> AsyncGenerator[str, None]:
        ...
