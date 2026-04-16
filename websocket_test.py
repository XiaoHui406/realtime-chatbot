import asyncio
import time
import soundfile as sf
import numpy as np
import websockets
from websockets import ClientConnection


async def send_audio(websocket: ClientConnection):
    chunk_size = 512
    waveform, sr = sf.read("./audio/hello-16k.mp3", dtype="float32")
    if sr != 16000:
        raise ValueError(f"{sr=}")
    await asyncio.to_thread(input)

    while len(waveform) > 0:
        chunk = waveform[:chunk_size]
        chunk_int16 = (chunk * 32767).astype(np.int16)
        waveform = waveform[chunk_size:]
        if len(chunk) == 512:
            await websocket.send(chunk_int16.tobytes())
            await asyncio.sleep(0.032)

    print("hello send finished")

    waveform, sr = sf.read("./audio/empty.mp3", dtype="float32")
    if sr != 16000:
        raise ValueError(f"{sr=}")
    await asyncio.to_thread(input)

    while len(waveform) > 0:
        chunk = waveform[:chunk_size]
        chunk_int16 = (chunk * 32767).astype(np.int16)
        waveform = waveform[chunk_size:]
        if len(chunk) == 512:
            await websocket.send(chunk_int16.tobytes())
            await asyncio.sleep(0.032)

    print("empty send finished")

    waveform, sr = sf.read("./audio/introduce-16k.mp3", dtype="float32")
    if sr != 16000:
        raise ValueError(f"{sr=}")
    await asyncio.to_thread(input)

    while len(waveform) > 0:
        chunk = waveform[:chunk_size]
        chunk_int16 = (chunk * 32767).astype(np.int16)
        waveform = waveform[chunk_size:]
        if len(chunk) == 512:
            await websocket.send(chunk_int16.tobytes())
            await asyncio.sleep(0.032)
    print("introduce send finished")

    # await websocket.send('exit')


async def receive_messages(websocket: ClientConnection):
    i = 0
    try:
        while True:
            msg: str | bytes = await websocket.recv()
            print(f"收到msg")
            assert type(msg) is bytes
            msg_bytes = np.frombuffer(msg, dtype='float32')

            sf.write(f'response_part{i}.wav', msg_bytes, 24000)
            i += 1

    except websockets.exceptions.ConnectionClosed:
        print("连接已关闭")


async def main():
    url = "ws://127.0.0.1:8000/realtime-chat"

    async with websockets.connect(url) as websocket:
        resp = await websocket.recv()
        print(resp)

        await asyncio.gather(
            send_audio(websocket), receive_messages(websocket)
        )

asyncio.run(main())
