from typing import List

from openai.types.chat import (
    ChatCompletionAssistantMessageParam,
    ChatCompletionMessageFunctionToolCallParam,
    ChatCompletionMessageParam,
    ChatCompletionSystemMessageParam,
    ChatCompletionToolMessageParam,
    ChatCompletionUserMessageParam,
)
from openai.types.chat.chat_completion_message_function_tool_call_param import Function
from sqlalchemy import select

from database_engine import get_database
from model.chatbot_session import ChatbotMessage, ChatbotToolCall


async def get_session_messages(
    session_id: int
) -> List[ChatCompletionMessageParam]:
    async with get_database() as database:
        messages_result = await database.execute(
            select(ChatbotMessage)
            .where(ChatbotMessage.session_id == session_id)
            .order_by(ChatbotMessage.created_at)
        )
        messages = messages_result.scalars().all()

        if not messages:
            return []

        message_ids = [message.id for message in messages]
        tool_calls_result = await database.execute(
            select(ChatbotToolCall)
            .where(ChatbotToolCall.message_id.in_(message_ids))
        )
        tool_calls_rows = tool_calls_result.scalars().all()

        tool_call_map: dict[int, List[ChatbotToolCall]] = {}
        for tool_call in tool_calls_rows:
            tool_call_map.setdefault(
                tool_call.message_id, []).append(tool_call)

        result: List[ChatCompletionMessageParam] = []
        for message in messages:
            if message.role == 'system':
                result.append(ChatCompletionSystemMessageParam(
                    role='system',
                    content=message.content,
                ))
            elif message.role == 'user':
                result.append(ChatCompletionUserMessageParam(
                    role='user',
                    content=message.content,
                ))
            elif message.role == 'assistant':
                tool_calls = tool_call_map.get(message.id, [])
                if tool_calls:
                    result.append(ChatCompletionAssistantMessageParam(
                        role='assistant',
                        content=message.content,
                        tool_calls=[
                            ChatCompletionMessageFunctionToolCallParam(
                                id=tool_call.tool_call_id,
                                type='function',
                                function=Function(
                                    name=tool_call.function_name,
                                    arguments=tool_call.function_arguments,
                                ),
                            )
                            for tool_call in tool_calls
                        ],
                    ))
                else:
                    result.append(ChatCompletionAssistantMessageParam(
                        role='assistant',
                        content=message.content,
                    ))
            elif message.role == 'tool':
                assert message.tool_call_id
                result.append(ChatCompletionToolMessageParam(
                    role='tool',
                    content=message.content,
                    tool_call_id=message.tool_call_id,
                ))
        return result
