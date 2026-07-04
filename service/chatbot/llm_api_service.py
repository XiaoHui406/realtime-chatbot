import asyncio
import json
from typing import Any, AsyncGenerator, Dict, List

from dotenv import load_dotenv

import os

from openai import AsyncOpenAI
from openai.types.chat import ChatCompletionMessageParam, \
    ChatCompletionSystemMessageParam, \
    ChatCompletionUserMessageParam, \
    ChatCompletionAssistantMessageParam, \
    ChatCompletionMessageFunctionToolCallParam
from openai.types.chat.chat_completion_message_function_tool_call_param import Function
from openai.types.chat.chat_completion_content_part_param import ChatCompletionContentPartParam

from service.chatbot.interface.chatbot_service import ChatbotService
from utils.tool_call import tool_manager_registry as tool_manager_reg


class LLMAPIService(ChatbotService):
    def __init__(
        self,
        initial_prompt: str | None = None
    ) -> None:
        load_dotenv()
        self.api_key = os.getenv("API_KEY")
        self.base_url = os.getenv("BASE_URL")
        self.llm_model = os.getenv("MODEL")
        assert self.api_key and self.base_url and self.llm_model

        self.client = AsyncOpenAI(
            base_url=self.base_url,
            api_key=self.api_key
        )
        self.messages: List[ChatCompletionMessageParam] = [
            ChatCompletionSystemMessageParam(
                role='system', content='这是一款ai语音聊天应用，用户的输入来自实时asr。回复保证只有一段话且使用纯文本不包含表情，禁止使用markdown格式回复')
        ]

        if initial_prompt:
            self.messages.append(
                ChatCompletionSystemMessageParam(
                    role='system', content=initial_prompt
                )
            )

    async def chat(self, message: List[ChatCompletionContentPartParam]) -> AsyncGenerator[str, None]:
        if not self.llm_model:
            raise ValueError('llm model is not set')
        if not tool_manager_reg.tool_manager:
            raise RuntimeError('tool_manager is not initialized')
        print(f'{self.messages=}')

        user_message = ChatCompletionUserMessageParam(
            role='user', content=message
        )
        self.messages.append(user_message)

        while True:
            # 发起请求并获得大模型的回复
            response_stream = await self.client.chat.completions.create(
                model=self.llm_model,
                messages=self.messages,
                stream=True,
                tools=await tool_manager_reg.tool_manager.agenerate_tools(),
                extra_body={
                    "thinking": {
                        "type": "disabled"
                    }
                }
            )

            response_content_list: List[str] = []
            tool_call_map: Dict[int,
                                ChatCompletionMessageFunctionToolCallParam] = {}
            tool_call_args_map: Dict[int, List[str]] = {}
            async for chunk in response_stream:
                choice = chunk.choices[0]
                delta = choice.delta
                # 大模型回复
                if delta.content:
                    print(f'{delta.content=}')
                    yield delta.content
                    response_content_list.append(delta.content)

                elif delta.tool_calls:
                    for tool_call in delta.tool_calls:
                        if tool_call.function:
                            if tool_call.id and tool_call.function.name:
                                tool_call_map[tool_call.index] = ChatCompletionMessageFunctionToolCallParam(
                                    id=tool_call.id,
                                    type='function',
                                    function=Function(
                                        name=tool_call.function.name,
                                        arguments=''
                                    )
                                )
                            elif tool_call.function.arguments:
                                print(f'{tool_call.function.arguments=}')
                                tool_call_args_map.setdefault(tool_call.index, []).append(
                                    tool_call.function.arguments
                                )
                elif not delta.tool_calls and choice.finish_reason == 'tool_calls':
                    for (index, tool_call) in tool_call_map.items():
                        tool_call['function']['arguments'] = ''.join(
                            tool_call_args_map[index])
                        self.messages.append(ChatCompletionAssistantMessageParam(
                            role='assistant',
                            content=None,
                            tool_calls=list(tool_call_map.values())
                        ))

                    tool_callbacks = await asyncio.gather(*(
                        tool_manager_reg.tool_manager.acall_tool(tool_call=tool_call) for tool_call in tool_call_map.values()
                    ))
                    self.messages.extend(tool_callbacks)

                elif choice.finish_reason == 'stop':
                    if response_content_list:
                        response_content = ''.join(response_content_list)
                        self.messages.append(ChatCompletionAssistantMessageParam(
                            role="assistant", content=response_content
                        ))
                    print(f'{self.messages=}')
                    return
                else:
                    continue
