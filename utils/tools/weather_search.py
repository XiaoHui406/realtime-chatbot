import httpx

from utils.tool_manager_registry import tool_manager


@tool_manager.agent_tool()
async def weather_search(city: str):
    """输入城市名称，返回城市天气信息"""
    async with httpx.AsyncClient() as client:
        response = await client.get(url=f'https://uapis.cn/api/v1/misc/weather?city={city}')
    return response.json()
