import json
import asyncio
import logging
import aiofiles
from contextlib import asynccontextmanager
from typing import AsyncGenerator, List, Dict, Set

import httpx
from openai.types.chat import (
    ChatCompletionFunctionToolParam,
    ChatCompletionMessageFunctionToolCallParam,
    ChatCompletionToolMessageParam,
)
from openai.types.shared_params import FunctionDefinition

from model.mcp_model import MCPLocalServer, MCPRemoteServer
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.sse import sse_client
from mcp.client.streamable_http import streamable_http_client
from mcp.types import TextContent

logger = logging.getLogger(__name__)


class MCPToolManager:

    def __init__(self):
        self._servers: Dict[str, MCPLocalServer | MCPRemoteServer] = {}
        self._tool_server_map: Dict[str, str] = {}

    @classmethod
    async def create(cls, mcp_config_path: str = './config.json'):
        instance = cls()
        await instance._init_mcp(mcp_config_path)
        return instance

    async def agenerate_tools(self) -> List[ChatCompletionFunctionToolParam]:
        tools: List[ChatCompletionFunctionToolParam] = []
        for server_name, server_config in self._servers.items():
            if not server_config.enabled:
                continue
            async with self._create_session(server_name) as session:
                try:
                    mcp_tools_result = await asyncio.wait_for(
                        session.list_tools(), timeout=server_config.timeout / 1000.0
                    )
                except BaseException as e:
                    if isinstance(e, (KeyboardInterrupt, SystemExit)):
                        raise
                    logger.warning(
                        f'Failed to list tools from MCP server: {server_name}: {e}'
                    )
                    continue

                for tool in mcp_tools_result.tools:
                    prefixed_name = f'{server_name}_{tool.name}'
                    tools.append(
                        ChatCompletionFunctionToolParam(
                            type='function',
                            function=FunctionDefinition(
                                name=prefixed_name,
                                description=tool.description or tool.name,
                                parameters=tool.inputSchema,
                            ),
                        )
                    )
                    self._tool_server_map[prefixed_name] = server_name
        return tools

    async def acall_tool(
        self, tool_call: ChatCompletionMessageFunctionToolCallParam
    ) -> ChatCompletionToolMessageParam:
        tool_name = tool_call['function']['name']
        arguments = json.loads(tool_call['function']['arguments'])
        tool_call_id = tool_call['id']

        server_name = self._tool_server_map.get(tool_name)
        if not server_name:
            raise ValueError(f'MCP tool not found: {tool_name}')

        server_config = self._servers[server_name]

        async with self._create_session(server_name) as session:
            actual_tool_name = tool_name[len(server_name) + 1:]

            try:
                result = await asyncio.wait_for(
                    session.call_tool(actual_tool_name, arguments),
                    timeout=server_config.timeout / 1000.0,
                )
            except Exception as e:
                content = json.dumps({'error': str(e)}, ensure_ascii=False)
            else:
                texts = [
                    item.text
                    for item in result.content
                    if isinstance(item, TextContent)
                ]
                content = ''.join(texts)

            return ChatCompletionToolMessageParam(
                role='tool',
                tool_call_id=tool_call_id,
                content=content,
            )

    async def _init_mcp(self, mcp_config_path: str = './config.json'):
        mcp_name_set: Set[str] = set()
        try:
            async with aiofiles.open(
                mcp_config_path, 'r', encoding='utf8'
            ) as config_file:
                configs = json.loads(await config_file.read())
        except FileNotFoundError:
            logger.warning('MCP config file not found: %s', mcp_config_path)
            return
        except json.JSONDecodeError as e:
            logger.error('Invalid MCP config file %s: %s', mcp_config_path, e)
            return
        mcp_configs: Dict[str, Dict] = configs.get('mcp', {})
        for mcp_name, mcp_config in mcp_configs.items():
            if mcp_name in mcp_name_set:
                raise ValueError(
                    f'MCP server name: {mcp_name} is duplicated'
                )
            mcp_name_set.add(mcp_name)
            if mcp_config.get('type') == 'local':
                self._servers[mcp_name] = MCPLocalServer(**mcp_config)
            elif mcp_config.get('type') == 'remote':
                self._servers[mcp_name] = MCPRemoteServer(**mcp_config)
            else:
                raise ValueError(
                    f'Unknown MCP server type: {mcp_config.get("type")}'
                )

    @asynccontextmanager
    async def _create_session(
        self, server_name: str
    ) -> AsyncGenerator[ClientSession, None]:
        server_config = self._servers.get(server_name)
        if not server_config:
            raise ValueError(
                f'MCP session not found for server: {server_name}')

        if server_config.type == 'local':
            command = server_config.command[0]
            args = server_config.command[1:]
            server_params = StdioServerParameters(
                command=command,
                args=args,
                env=server_config.environment,
            )
            async with stdio_client(server_params) as (receiver, sender):
                async with ClientSession(receiver, sender) as session:
                    await session.initialize()
                    yield session
        elif server_config.type == 'remote':
            async with self._connect_remote(server_config) as session:
                yield session

    @asynccontextmanager
    async def _connect_remote(
        self, server_config
    ) -> AsyncGenerator[ClientSession, None]:
        setup_success = False
        streamable_http_error = None
        try:
            async with streamable_http_client(
                url=server_config.url,
                http_client=httpx.AsyncClient(
                    headers=server_config.headers,
                    timeout=server_config.timeout / 1000.0,
                ),
            ) as (receiver, sender, _):
                async with ClientSession(receiver, sender) as session:
                    await session.initialize()
                    setup_success = True
                    yield session
        except Exception as e:
            if not setup_success:
                streamable_http_error = e
                logger.debug(
                    'streamable_http failed for %s: %s',
                    server_config.url, e,
                )
            else:
                raise
        else:
            return

        try:
            async with sse_client(
                url=server_config.url,
                headers=server_config.headers,
                timeout=server_config.timeout / 1000.0,
            ) as (receiver, sender):
                async with ClientSession(receiver, sender) as session:
                    await session.initialize()
                    setup_success = True
                    yield session
        except Exception as e:
            if not setup_success:
                raise RuntimeError(
                    f'Failed to connect to remote MCP server '
                    f'{server_config.url}. '
                    f'streamable_http error: {streamable_http_error}, '
                    f'sse error: {e}'
                ) from e
            raise
