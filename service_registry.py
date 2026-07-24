import asyncio
from concurrent.futures import ThreadPoolExecutor
from faster_qwen3_tts import FasterQwen3TTS
import funasr
from silero_vad import load_silero_vad

from service.asr.interface.asr_service import ASRService
from service.tts.interface.tts_service import TTSService
from service.tts.qwen_tts_service import QwenTTSService
from service.asr.sensevoice_service import SenseVoiceService
from service.asr.whisper_service import WhisperService
from service.chatbot.interface.chatbot_service import ChatbotService
from service.chatbot.llm_api_service import LLMAPIService


from utils.client_request_manager import ClientRequestManager

sensevoice_model: funasr.AutoModel | None = None
qwen3tts_model: FasterQwen3TTS | None = None

asr_service: ASRService | None = None
tts_service: TTSService | None = None
chatbot_service: ChatbotService = LLMAPIService()
vad_model = None
client_request_manager = ClientRequestManager()


async def init_service():
    global asr_service, tts_service, vad_model, sensevoice_model, qwen3tts_model

    loop = asyncio.get_running_loop()
    with ThreadPoolExecutor(max_workers=3) as pool:
        f_asr_model = loop.run_in_executor(pool, load_sensevoice_model)
        f_tts_model = loop.run_in_executor(pool, load_qwen3tts_model)
        f_vad_model = loop.run_in_executor(pool, load_silero_vad)

        sensevoice_model, qwen3tts_model, vad_model = await asyncio.gather(
            f_asr_model, f_tts_model, f_vad_model
        )
    with ThreadPoolExecutor(max_workers=2) as pool:
        f_asr = loop.run_in_executor(pool, SenseVoiceService, sensevoice_model)
        f_tts = loop.run_in_executor(pool, QwenTTSService, qwen3tts_model)

        asr_service, tts_service = await asyncio.gather(
            f_asr, f_tts
        )


def load_sensevoice_model():
    try:
        model = funasr.AutoModel(
            model='iic/SenseVoiceSmall',
            device='cuda:0'
        )
    except NotImplementedError:
        model = funasr.AutoModel(
            model='iic/SenseVoiceSmall',
            device='cpu'
        )
        device = 'cuda:0'
        model.model.to(device)
        model.kwargs['device'] = 'cuda:0'  # type: ignore
        model._base_kwargs_map['kwargs']['device'] = 'cuda:0'
    return model


def load_qwen3tts_model():
    return FasterQwen3TTS.from_pretrained(
        model_name='Qwen/Qwen3-TTS-12Hz-0.6B-Base'
    )
