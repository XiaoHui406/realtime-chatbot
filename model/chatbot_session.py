from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict
from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from database_engine import Base


@dataclass
class ChatBotSession(Base):
    __tablename__ = 'chatbot_session'

    id: Mapped[int] = mapped_column(
        Integer, autoincrement=True, primary_key=True)
    title: Mapped[Optional[str]] = mapped_column(
        String, nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.now)


@dataclass
class ChatbotMessage(Base):
    __tablename__ = 'chatbot_message'

    id: Mapped[int] = mapped_column(
        Integer, autoincrement=True, primary_key=True)
    session_id: Mapped[int] = mapped_column(
        Integer, ForeignKey('chatbot_session.id', ondelete='CASCADE'), nullable=False)
    role: Mapped[str] = mapped_column(
        String, nullable=False)
    content: Mapped[Any] = mapped_column(
        JSON, nullable=True)
    tool_call_id: Mapped[Optional[str]] = mapped_column(
        String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.now)


@dataclass
class ChatbotToolCall(Base):
    __tablename__ = 'chatbot_tool_call'

    id: Mapped[int] = mapped_column(
        Integer, autoincrement=True, primary_key=True)
    message_id: Mapped[int] = mapped_column(
        Integer, ForeignKey('chatbot_message.id', ondelete='CASCADE'), nullable=False)
    tool_call_id: Mapped[str] = mapped_column(
        String, nullable=False)
    function_name: Mapped[str] = mapped_column(
        String, nullable=False)
    function_arguments: Mapped[str] = mapped_column(
        JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.now)


class CreateSessionSchema(BaseModel):
    initial_prompt: str | None = None
    title: str | None = None


class ChatBotSessionResponse(BaseModel):
    id: int
    title: str | None = None
    created_at: datetime
    updated_at: datetime


class ChatbotMessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    session_id: int
    role: str
    content: Any | None = None
    tool_call_id: str | None = None
    created_at: datetime
