from datetime import datetime
from typing import List

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import desc, select

from database_engine import get_database
from model.chatbot_session import ChatBotSession, ChatBotSessionResponse, ChatbotMessage, ChatbotMessageResponse, CreateSessionSchema
import service_registry

from openai.types.chat import ChatCompletionMessageParam


chatbot_session_router = APIRouter(
    prefix='/chatbot_session',
    tags=['chatbot_session']
)


@chatbot_session_router.get('', response_model=List[ChatBotSessionResponse])
async def get_session_list(limit: int = Query(default=50, le=200), offset: int = Query(default=0, ge=0)):
    session_list: List[ChatBotSessionResponse] = []
    async with get_database() as database:
        result = await database.execute(
            select(ChatBotSession)
            .order_by(desc(ChatBotSession.updated_at))
            .offset(offset)
            .limit(limit)
        )
        sessions = result.scalars().all()
        for session in sessions:
            session_list.append(ChatBotSessionResponse(
                id=session.id, title=session.title,
                created_at=session.created_at, updated_at=session.updated_at
            ))
    return session_list


@chatbot_session_router.post('', response_model=ChatBotSessionResponse)
async def create_session(create_session_schema: CreateSessionSchema):
    chatbot_session = ChatBotSession()
    if create_session_schema.title:
        chatbot_session.title = create_session_schema.title
    async with get_database() as database:
        database.add(chatbot_session)
        await database.commit()
        await database.refresh(chatbot_session)

        system_message = ChatbotMessage(
            session_id=chatbot_session.id,
            role='system',
            content='这是一款ai语音聊天应用，用户的输入来自实时asr。你的回复会被tts转为音频，所以回复保证只有一段话且使用纯文本不包含表情，禁止使用markdown格式回复'
        )
        database.add(system_message)

        if create_session_schema.initial_prompt:
            chatbot_message = ChatbotMessage(
                session_id=chatbot_session.id,
                role='system',
                content=create_session_schema.initial_prompt
            )
            database.add(chatbot_message)
        await database.commit()
        await database.refresh(chatbot_session)
    session_response = ChatBotSessionResponse(
        id=chatbot_session.id,
        title=chatbot_session.title,
        created_at=chatbot_session.created_at,
        updated_at=chatbot_session.updated_at
    )
    return session_response


@chatbot_session_router.put('/{session_id}', response_model=str)
async def edit_session(session_id: int, title: str):
    async with get_database() as database:
        result = await database.execute(
            select(ChatBotSession)
            .filter(ChatBotSession.id == session_id)
        )
        session = result.scalars().one_or_none()
        if not session:
            raise HTTPException(
                status_code=404, detail=f'session is not exist, session_id: {session_id}')
        session.title = title
        session.updated_at = datetime.now()
        await database.commit()
    return 'session has been successfully edited'


@chatbot_session_router.get('/{session_id}/messages', response_model=List[ChatbotMessageResponse])
async def get_session_messages(session_id: int):
    async with get_database() as database:
        result = await database.execute(
            select(ChatbotMessage)
            .filter(ChatbotMessage.session_id == session_id)
            .order_by(ChatbotMessage.created_at)
        )
        messages = result.scalars().all()
        return [ChatbotMessageResponse(
            id=msg.id,
            session_id=msg.session_id,
            role=msg.role,
            content=msg.content,
            tool_call_id=msg.tool_call_id,
            created_at=msg.created_at,
        ) for msg in messages]


@chatbot_session_router.delete('/{session_id}', response_model=str)
async def delete_session(session_id: int):
    async with get_database() as database:
        result = await database.execute(
            select(ChatBotSession)
            .filter(ChatBotSession.id == session_id)
        )
        session = result.scalars().one_or_none()
        if not session:
            raise HTTPException(
                status_code=404, detail=f'session is not exist, session_id: {session_id}')
        await database.delete(session)
        await database.commit()
    return 'session has been successfully deleted'
