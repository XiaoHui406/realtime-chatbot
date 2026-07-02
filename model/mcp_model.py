from typing import Dict, List, Literal

from pydantic import BaseModel, Field


class MCPLocalServer(BaseModel):
    type: Literal['local'] = 'local'
    command: List[str]
    environment: Dict[str, str] | None = None
    enabled: bool = True
    timeout: int = 5000  # 5000ms


class MCPRemoteServer(BaseModel):
    type: Literal['remote'] = 'remote'
    url: str
    enabled: bool = True
    headers: Dict[str, str] | None = None
    timeout: int = 5000  # 5000ms
