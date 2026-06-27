from dataclasses import dataclass
from datetime import datetime

from pydantic import BaseModel
from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from database_engine import Base


@dataclass
class ReferenceAudio(Base):
    __tablename__ = 'reference_audio'

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, default='未命名音频')
    file_path: Mapped[str] = mapped_column(String, nullable=False)
    transcribe_text: Mapped[str] = mapped_column(String, nullable=False)
    tags: Mapped[str] = mapped_column(String)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.now)


class ReferenceAudioResponse(BaseModel):
    id: int
    name: str
    tags: str
