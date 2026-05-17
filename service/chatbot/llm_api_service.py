from typing import Any, AsyncGenerator, Dict, List

from dotenv import load_dotenv

import os

from openai import AsyncOpenAI
from openai.types.shared_params import FunctionDefinition, FunctionParameters
from openai.types.chat import ChatCompletionMessageParam, \
    ChatCompletionSystemMessageParam, \
    ChatCompletionUserMessageParam, \
    ChatCompletionAssistantMessageParam, \
    ChatCompletionToolMessageParam, \
    ChatCompletionFunctionToolParam

from service.chatbot.interface.chatbot_service import ChatbotService


class LLMApiService(ChatbotService):
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
                role='system',
                content='用户的输入来自实时asr，如果你觉得用户没说完，请调用no_reply方法。回复保证只有一段话且使用纯文本，禁止使用markdown格式回复'),
        ]

        if initial_prompt:
            self.messages.append(
                ChatCompletionSystemMessageParam(
                    role='system', content=initial_prompt
                )
            )

        # call_no_reply初始为false，在大模型调用no_reply后变为true
        self.call_no_reply: bool = False

    async def chat(self, message: str) -> AsyncGenerator[str, None]:
        assert self.llm_model
        print(f'{self.messages=}')

        while True:
            last_message_content = ''
            # 如果不回复，则把这次message拼接到上次message中
            if self.call_no_reply:
                last_message = self.messages.pop()
                print(f'{last_message=}')
                assert type(last_message) is ChatCompletionUserMessageParam and type(
                    last_message['content']) is str
                last_message_content = last_message['content']
                # 拼接完成后，把call_no_reply置为false，并继续运行
                self.call_no_reply = False

            # 将消息放入消息列表里
            last_message_content += message
            user_message = ChatCompletionUserMessageParam(
                role='user', content=last_message_content
            )
            self.messages.append(user_message)

            # 发起请求并获得大模型的回复
            response_stream = await self.client.chat.completions.create(
                model=self.llm_model,
                messages=self.messages,
                tools=[no_reply_json_schema],
                stream=True
            )

            response_content_list: List[str] = []
            async for chunk in response_stream:
                delta = chunk.choices[0].delta
                # 大模型回复
                if delta.content:
                    print(f'{delta.content=}')
                    yield delta.content
                    response_content_list.append(delta.content)

                elif delta.tool_calls:
                    for tool_call in delta.tool_calls:
                        # 大模型调用no_reply方法
                        # 将call_no_reply置为true并结束执行
                        if tool_call.function and tool_call.function.name == 'no_reply':
                            self.call_no_reply = True
                            return

            # 回复列表长度大于0，说明有回复
            # 把回复存入消息列表
            if len(response_content_list) > 0:
                response_message = ''.join(response_content_list)
                print(f'{response_message=}')
                self.messages.append(
                    ChatCompletionAssistantMessageParam(
                        role='assistant', content=response_message
                    )
                )
                return


no_reply_json_schema = ChatCompletionFunctionToolParam(
    type='function',
    function=FunctionDefinition(
        name='no_reply',
        description='如果你觉得用户没有说完，请调用该方法表示不回复',
        parameters={
            'type': 'object',
            "properties": {},
        }
    )
)
