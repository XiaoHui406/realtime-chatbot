from utils.tool_call.tool_manager_registry import agent_tool_manager
from service_registry import client_request_manager


@agent_tool_manager.agent_tool()
async def get_location():
    """获取用户设备当前的地理位置信息（经纬度）"""
    result = await client_request_manager.request('get_location')
    return result
