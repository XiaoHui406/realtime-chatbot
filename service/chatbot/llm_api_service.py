import asyncio
import json
import re
from datetime import datetime
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
from utils.chatbot_session_utils import get_session_messages
from utils.tool_call import tool_manager_registry as tool_manager_reg

from database_engine import get_database
from model.chatbot_session import ChatBotSession, ChatbotMessage, ChatbotToolCall


_EMOJI_RE = re.compile(
    "["
    "\U0001F600-\U0001F9FF"
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "\U00002702-\U000027B0"
    "\U00002600-\U000027BF"
    "\U0001F300-\U0001F5FF"
    "\U0001F680-\U0001F6FF"
    "\U0001F1E0-\U0001F1FF"
    "]+",
    flags=re.UNICODE,
)


def _strip_chunk(text: str) -> str:
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'`(.+?)`', r'\1', text)
    text = re.sub(r'~~(.+?)~~', r'\1', text)
    text = re.sub(r'^#{1,6}\s', '', text, flags=re.MULTILINE)
    text = _EMOJI_RE.sub('', text)
    return text


class LLMAPIService(ChatbotService):
    def __init__(self) -> None:
        load_dotenv()
        self.api_key = os.getenv("API_KEY")
        self.base_url = os.getenv("BASE_URL")
        self.llm_model = os.getenv("MODEL")
        if not self.api_key:
            raise ValueError('API_KEY is not set in .env')
        if not self.base_url:
            raise ValueError('BASE_URL is not set in .env')
        if not self.llm_model:
            raise ValueError('MODEL is not set in .env')

        self.client = AsyncOpenAI(
            base_url=self.base_url,
            api_key=self.api_key
        )
        self.messages: List[ChatCompletionMessageParam] = []
        self._session_id: int | None = None

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
        await self._save_message(user_message)

        while True:
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
                if len(response_content_list) > 0 and delta.tool_calls:
                    response_content = ''.join(response_content_list)
                    assistant_msg = ChatCompletionAssistantMessageParam(
                        role='assistant', content=response_content
                    )
                    self.messages.append(assistant_msg)
                    await self._save_message(assistant_msg)
                    response_content_list = []

                if delta.content:
                    print(f'{delta.content=}')
                    filtered = _strip_chunk(delta.content)
                    if filtered:
                        yield filtered
                        response_content_list.append(filtered)

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
                    tool_calls_list = list(tool_call_map.values())
                    for (index, tc) in tool_call_map.items():
                        tc['function']['arguments'] = ''.join(
                            tool_call_args_map.get(index, []))

                    assistant_msg = ChatCompletionAssistantMessageParam(
                        role='assistant',
                        content=None,
                        tool_calls=tool_calls_list
                    )
                    self.messages.append(assistant_msg)
                    await self._save_message(assistant_msg)

                    tool_callbacks = await asyncio.gather(*(
                        tool_manager_reg.tool_manager.acall_tool(tool_call=tc) for tc in tool_calls_list
                    ))
                    self.messages.extend(tool_callbacks)
                    for callback in tool_callbacks:
                        await self._save_message(callback)

                elif choice.finish_reason == 'stop':
                    if response_content_list:
                        response_content = ''.join(response_content_list)
                        assistant_msg = ChatCompletionAssistantMessageParam(
                            role="assistant", content=response_content
                        )
                        self.messages.append(assistant_msg)
                        await self._save_message(assistant_msg)
                    print(f'{self.messages=}')
                    return
                else:
                    continue

    async def set_session(self, session_id: int) -> None:
        self._session_id = session_id
        self.messages = await get_session_messages(session_id)

    async def _ensure_session(self):
        if self._session_id is not None:
            return
        async with get_database() as db:
            session = ChatBotSession()
            db.add(session)
            await db.commit()
            await db.refresh(session)
            self._session_id = session.id
            assert self._session_id is not None

            for msg in self.messages:
                db.add(ChatbotMessage(
                    session_id=self._session_id,
                    role=msg['role'],
                    content=msg.get('content'),
                ))
            await db.commit()

    async def _save_message(self, message: ChatCompletionMessageParam):
        await self._ensure_session()
        assert self._session_id
        async with get_database() as db:
            db_msg = ChatbotMessage(
                session_id=self._session_id,
                role=message['role'],
                content=message.get('content'),
                tool_call_id=message.get('tool_call_id'),
            )
            db.add(db_msg)
            await db.flush()

            tool_calls = message.get('tool_calls')
            if tool_calls:
                for tool_call in tool_calls:
                    func = tool_call.get('function')
                    if func:
                        db.add(ChatbotToolCall(
                            message_id=db_msg.id,
                            tool_call_id=tool_call['id'],
                            function_name=func['name'],
                            function_arguments=func['arguments'],
                        ))

            session = await db.get(ChatBotSession, self._session_id)
            if session:
                session.updated_at = datetime.now()
            await db.commit()
