from typing import Dict, List

from utils.tool_call.interface.tool_manager import ToolManager
from openai.types.chat import ChatCompletionFunctionToolParam, \
    ChatCompletionMessageFunctionToolCallParam, \
    ChatCompletionToolMessageParam


class ToolManagerProxy:

    def __init__(self) -> None:
        self.tool_managers: List[ToolManager] = []
        self.call_tool_map: Dict[str, ToolManager] = {}

    @classmethod
    async def create(cls, tool_managers: List[ToolManager]):
        instance = cls()
        await instance._init_call_tool_map(tool_managers)
        return instance

    async def agenerate_tools(self) -> List[ChatCompletionFunctionToolParam]:
        tools: List[ChatCompletionFunctionToolParam] = []
        for manager in self.tool_managers:
            tools.extend(await manager.agenerate_tools())
        return tools

    async def acall_tool(
        self, tool_call: ChatCompletionMessageFunctionToolCallParam
    ) -> ChatCompletionToolMessageParam:
        manager = self.call_tool_map[tool_call['function']['name']]
        return await manager.acall_tool(tool_call)

    async def _init_call_tool_map(self, tool_managers: List[ToolManager]) -> None:
        call_tool_map: Dict[str, ToolManager] = {}
        tool_name_set: set[str] = set()
        for manager in tool_managers:
            manager_tools = await manager.agenerate_tools()
            for tool in manager_tools:
                if tool['function']['name'] not in tool_name_set:
                    call_tool_map[tool['function']['name']] = manager
                    tool_name_set.add(tool['function']['name'])
                else:
                    raise ValueError(
                        f'tool name: {tool["function"]["name"]} is duplicated')
        self.tool_managers = tool_managers
        self.call_tool_map = call_tool_map
