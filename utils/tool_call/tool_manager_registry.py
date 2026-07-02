from utils.tool_call.agent_tool_manager import AgentToolManager, load_tools
from utils.tool_call.interface.tool_manager import ToolManager
from utils.tool_call.mcp_tool_manager import MCPToolManager
from utils.tool_call.tool_manager_proxy import ToolManagerProxy


agent_tool_manager = AgentToolManager()
mcp_tool_manager: MCPToolManager | None = None

tool_manager: ToolManager | None = None


async def init_tool_manager() -> None:
    global tool_manager, mcp_tool_manager
    if not tool_manager:
        if not mcp_tool_manager:
            mcp_tool_manager = await MCPToolManager.create()
        tool_manager = await ToolManagerProxy.create(
            [agent_tool_manager, mcp_tool_manager])


load_tools('utils.tool_call.tools')
