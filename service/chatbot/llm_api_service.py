import asyncio
import json
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
from utils.latency_tracer import tracer
from utils.text_sanitizer import strip_markdown
from utils.tool_call import tool_manager_registry as tool_manager_reg

from database_engine import get_database
from model.chatbot_session import ChatBotSession, ChatbotMessage, ChatbotToolCall


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
        self._pending_messages: List[ChatCompletionMessageParam] = []

    async def warmup(self) -> None:
        """发送一次极小的请求，预热TCP+TLS连接，降低首次对话的TTFT"""
        if not self.llm_model:
            return
        try:
            await self.client.chat.completions.create(
                model=self.llm_model,
                messages=[ChatCompletionUserMessageParam(
                    role='user', content='hi')],
                max_tokens=1,
                extra_body={
                    "thinking": {
                        "type": "disabled"
                    }
                }
            )
        except Exception as e:
            # 预热失败不影响正常流程
            print(f'llm warmup failed: {e}')

    async def chat(self, message: List[ChatCompletionContentPartParam]) -> AsyncGenerator[str, None]:
        if not self.llm_model:
            raise ValueError('llm model is not set')
        if not tool_manager_reg.tool_manager:
            raise RuntimeError('tool_manager is not initialized')

        user_message = ChatCompletionUserMessageParam(
            role='user', content=message
        )
        self.messages.append(user_message)
        await self._save_message(user_message)

        try:
            while True:
                # 打点：向LLM发起请求
                tracer.mark("llm_request_start", first_only=True)
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
                        # 完整文本上去除markdown后再入库
                        # (流式delta会把成对标记拆开，只能在拼接后的全文上处理)
                        response_content = strip_markdown(
                            ''.join(response_content_list))
                        assistant_msg = ChatCompletionAssistantMessageParam(
                            role='assistant', content=response_content
                        )
                        self.messages.append(assistant_msg)
                        await self._save_message(assistant_msg)
                        response_content_list = []

                    if delta.content:
                        # 原样流式下发，markdown清理由下游在完整句子上执行
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

                        collected_images: List[str] = []
                        for tool_callback in tool_callbacks:
                            content = tool_callback.get('content', '')
                            if isinstance(content, str):
                                try:
                                    data = json.loads(content)
                                    if isinstance(data, dict):
                                        images = data.get('images', [])
                                        if isinstance(images, list) and images:
                                            collected_images.extend(images)
                                            tool_callback['content'] = json.dumps(
                                                {'message': data.get(
                                                    'message', 'completed')},
                                                ensure_ascii=False,
                                            )
                                            continue
                                except (json.JSONDecodeError, TypeError, AttributeError):
                                    pass

                        self.messages.extend(tool_callbacks)
                        for callback in tool_callbacks:
                            await self._save_message(callback)

                        if collected_images:
                            image_parts: List[ChatCompletionContentPartParam] = [
                            ]
                            for img_url in collected_images:
                                image_parts.append({
                                    'type': 'image_url',
                                    'image_url': {'url': img_url, 'detail': 'auto'},
                                })
                            image_user_msg = ChatCompletionUserMessageParam(
                                role='user',
                                content=image_parts,
                            )
                            self.messages.append(image_user_msg)
                            await self._save_message(image_user_msg)

                    elif choice.finish_reason == 'stop':
                        if response_content_list:
                            # 完整文本上去除markdown后再入库
                            response_content = strip_markdown(
                                ''.join(response_content_list))
                            assistant_msg = ChatCompletionAssistantMessageParam(
                                role="assistant", content=response_content
                            )
                            self.messages.append(assistant_msg)
                            await self._save_message(assistant_msg)
                        return
                    else:
                        continue
        finally:
            await self._flush_pending_messages()

    async def set_session(self, session_id: int) -> None:
        await self._flush_pending_messages()
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

    async def _save_message(self, message: ChatCompletionMessageParam):
        await self._ensure_session()
        self._pending_messages.append(message)

    async def _flush_pending_messages(self):
        if not self._pending_messages:
            return
        assert self._session_id is not None
        async with get_database() as db:
            orm_msgs = []
            for msg in self._pending_messages:
                db_msg = ChatbotMessage(
                    session_id=self._session_id,
                    role=msg['role'],
                    content=msg.get('content'),
                    tool_call_id=msg.get('tool_call_id'),
                )
                db.add(db_msg)
                orm_msgs.append(db_msg)
            await db.flush()

            for pending, orm_msg in zip(self._pending_messages, orm_msgs):
                tool_calls = pending.get('tool_calls')
                if tool_calls:
                    for tc in tool_calls:
                        func = tc.get('function')
                        if func:
                            db.add(ChatbotToolCall(
                                message_id=orm_msg.id,
                                tool_call_id=tc['id'],
                                function_name=func['name'],
                                function_arguments=func['arguments'],
                            ))

            session = await db.get(ChatBotSession, self._session_id)
            if session:
                session.updated_at = datetime.now()
            await db.commit()
        self._pending_messages.clear()
