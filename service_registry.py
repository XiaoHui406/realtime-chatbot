import asyncio
from concurrent.futures import ThreadPoolExecutor
from silero_vad import load_silero_vad

from service.asr.interface.asr_service import ASRService
from service.tts.interface.tts_service import TTSService
from service.tts.qwen_tts_service import QwenTTSService
from service.asr.sensevoice_service import SenseVoiceService
from service.asr.whisper_service import WhisperService


from utils.client_request_manager import ClientRequestManager

asr_service: ASRService | None = None
tts_service: TTSService | None = None
vad_model = None
client_request_manager = ClientRequestManager()


async def init_service():
    global asr_service, tts_service, vad_model

    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor(max_workers=3) as pool:
        f_asr = loop.run_in_executor(pool, SenseVoiceService)
        f_tts = loop.run_in_executor(pool, QwenTTSService)
        f_vad = loop.run_in_executor(pool, load_silero_vad)

        asr_service, tts_service, vad_model = await asyncio.gather(
            f_asr, f_tts, f_vad
        )
        vad_model = vad_model.to(device)  # type: ignore
