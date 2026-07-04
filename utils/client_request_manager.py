import asyncio
import json
import uuid
from typing import Any, Dict, Optional

from fastapi import WebSocket


class ClientNotConnectedError(Exception):
    pass


class ClientRequestTimeoutError(Exception):
    pass


class ClientRequestManager:
    def __init__(self):
        self._websocket: WebSocket | None = None
        self._pending: Dict[str, asyncio.Future] = {}

    def set_websocket(self, ws: WebSocket | None) -> None:
        self._websocket = ws

    def is_connected(self) -> bool:
        return self._websocket is not None

    async def request(
        self,
        action: str,
        data: Optional[Dict[str, Any]] = None,
        timeout: float = 10.0,
    ) -> Dict[str, Any]:
        if not self._websocket:
            raise ClientNotConnectedError('WebSocket is not connected')

        request_id = str(uuid.uuid4())[:8]
        loop = asyncio.get_running_loop()
        future = loop.create_future()
        self._pending[request_id] = future

        try:
            await self._websocket.send_text(json.dumps({
                'type': 'request',
                'action': action,
                'request_id': request_id,
                'data': data or {},
            }, ensure_ascii=False))
        except Exception:
            self._pending.pop(request_id, None)
            raise

        try:
            return await asyncio.wait_for(future, timeout=timeout)
        except asyncio.TimeoutError:
            self._pending.pop(request_id, None)
            raise ClientRequestTimeoutError(
                f'Client did not respond to "{action}" within {timeout}s')
        except asyncio.CancelledError:
            self._pending.pop(request_id, None)
            raise

    def handle_response(self, request_id: str, result: Dict[str, Any]) -> None:
        future = self._pending.pop(request_id, None)
        if future is not None:
            if not future.done():
                future.set_result(result)

    def cancel_all(self) -> None:
        for request_id, future in list(self._pending.items()):
            if not future.done():
                future.cancel()
        self._pending.clear()
