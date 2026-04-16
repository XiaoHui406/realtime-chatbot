from pydantic import BaseModel


class Timestamp(BaseModel):
    start: float
    end: float
