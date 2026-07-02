import httpx

from utils.tool_call.tool_manager_registry import agent_tool_manager


# 被装饰器装饰的方法的返回值需要能被json.dumps转为str
@agent_tool_manager.agent_tool()
async def weather_search(city: str):
    """输入城市名称，返回城市天气信息"""
    async with httpx.AsyncClient() as client:
        response = await client.get(url=f'https://uapis.cn/api/v1/misc/weather?city={city}')
    return response.json()
