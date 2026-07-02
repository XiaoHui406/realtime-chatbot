from typing import List, Protocol
from openai.types.chat import ChatCompletionFunctionToolParam, \
    ChatCompletionMessageFunctionToolCallParam, \
    ChatCompletionToolMessageParam


class ToolManager(Protocol):
    async def agenerate_tools(self) -> List[ChatCompletionFunctionToolParam]:
        ...

    async def acall_tool(
        self, tool_call: ChatCompletionMessageFunctionToolCallParam
    ) -> ChatCompletionToolMessageParam:
        ...
