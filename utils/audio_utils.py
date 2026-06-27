import asyncio
import logging
import os
import subprocess
import tempfile

import numpy as np
import torch
import torchaudio
import torchaudio.functional as AF

logger = logging.getLogger(__name__)

TARGET_SAMPLE_RATE = 16000


def _load_with_torchaudio(file_path: str) -> tuple[torch.Tensor, int]:
    return torchaudio.load(file_path)


def _load_with_ffmpeg(file_path: str, target_sr: int) -> tuple[torch.Tensor, int]:
    proc = subprocess.run(
        [
            'ffmpeg',
            '-i', file_path,
            '-vn',
            '-acodec', 'pcm_s16le',
            '-ar', str(target_sr),
            '-ac', '1',
            '-f', 's16le',
            'pipe:1',
        ],
        capture_output=True,
        check=True,
    )
    audio_int16 = np.frombuffer(proc.stdout, dtype=np.int16)
    waveform = torch.from_numpy(audio_int16.astype(
        np.float32) / 32768.0).unsqueeze(0)
    return waveform, target_sr


def _resample_waveform(waveform: torch.Tensor, orig_sr: int, target_sr: int) -> torch.Tensor:
    if orig_sr == target_sr:
        return waveform
    return AF.resample(waveform, orig_sr, target_sr)


def _to_mono(waveform: torch.Tensor) -> torch.Tensor:
    if waveform.shape[0] == 1:
        return waveform
    return waveform.mean(dim=0, keepdim=True)


async def preprocess_audio_to_waveform(
    audio_bytes: bytes,
    target_sr: int = TARGET_SAMPLE_RATE,
    filename_hint: str = '',
) -> np.ndarray:
    suffix = os.path.splitext(filename_hint)[1] or '.wav'
    fd, tmp_path = tempfile.mkstemp(suffix=suffix)
    try:
        with open(fd, 'wb') as f:
            f.write(audio_bytes)

        waveform: torch.Tensor
        orig_sr: int

        try:
            waveform, orig_sr = _load_with_torchaudio(tmp_path)
        except Exception:
            logger.debug('torchaudio load failed, falling back to ffmpeg')
            waveform, orig_sr = await asyncio.to_thread(_load_with_ffmpeg, tmp_path, target_sr)

        waveform = _to_mono(waveform)
        waveform = _resample_waveform(waveform, orig_sr, target_sr)

        return waveform.squeeze(0).numpy().astype(np.float32)

    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
