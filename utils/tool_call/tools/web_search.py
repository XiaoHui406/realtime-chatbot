import json
from typing import Dict, List
from dotenv import load_dotenv
import httpx
import os

from utils.tool_call.tool_manager_registry import agent_tool_manager
from pydantic import BaseModel, Field


class WebSearchParams(BaseModel):
    content: str = Field(description='搜索内容')
    search_count: int = Field(description='搜索数量', default=5)


load_dotenv()
zai_api_key: str | None = os.getenv('ZAI_API_KEY')
if not zai_api_key:
    raise ValueError('zhipu apikey is None, web search tool is disabled')


@agent_tool_manager.agent_tool(InputClass=WebSearchParams)
async def web_search(web_search_params: WebSearchParams) -> List[Dict]:
    """
    输入搜索内容和搜索数量，返回联网搜索结果
    """
    async with httpx.AsyncClient() as client:
        search_response = await client.post(
            url='https://open.bigmodel.cn/api/paas/v4/web_search',
            headers={
                "Authorization": f"Bearer {zai_api_key}",
                "Content-Type": "application/json"
            },
            json={
                "search_engine": "search-std",
                "search_intent": False,
                "search_query": web_search_params.content,
                "count": web_search_params.search_count
            }
        )
    result_list: List[Dict] = []
    search_results = search_response.json()['search_result']
    for search_result in search_results:
        title: str = search_result['title']
        content: str = search_result['content']
        publish_date: str = search_result['publish_date']
        result_list.append({
            "publish_date": publish_date,
            "title": title,
            "content": content
        })
    return result_list
