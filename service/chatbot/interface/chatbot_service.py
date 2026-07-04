from abc import ABC, abstractmethod
from typing import AsyncGenerator, List

from openai.types.chat.chat_completion_content_part_param import ChatCompletionContentPartParam


class ChatbotService(ABC):

    @abstractmethod
    def chat(self, message: List[ChatCompletionContentPartParam]) -> AsyncGenerator[str, None]:
        ...
