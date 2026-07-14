from abc import ABC, abstractmethod
from typing import AsyncGenerator, List

from openai.types.chat import ChatCompletionMessageParam
from openai.types.chat.chat_completion_content_part_param import ChatCompletionContentPartParam


class ChatbotService(ABC):

    @abstractmethod
    def chat(self, message: List[ChatCompletionContentPartParam]) -> AsyncGenerator[str, None]:
        ...

    @abstractmethod
    async def set_session(self, session_id: int) -> None:
        ...

    async def warmup(self) -> None:
        """预热底层连接（如TCP+TLS握手），把连接建立成本移出对话路径。默认无操作"""
        return
