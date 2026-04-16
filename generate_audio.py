from faster_qwen3_tts import FasterQwen3TTS
import soundfile as sf

ref_audio = './audio/part1.aac'
ref_text = '我说过了嘛就是这种视频，其实就是单纯听一个人叨叨叨，然后就，可能会睡着，或者是觉得没那么无聊'


model = FasterQwen3TTS.from_pretrained(
    'Qwen/Qwen3-TTS-12Hz-0.6B-Base'
)

audio_list, sr = model.generate_voice_clone(
    text='你好', language='Chinese',
    ref_audio=ref_audio, ref_text=ref_text
)
sf.write('hello.mp3', audio_list[0], sr)

audio_list, sr = model.generate_voice_clone(
    text='请你做个简单的自我介绍', language='Chinese',
    ref_audio=ref_audio, ref_text=ref_text
)
sf.write('introduce.mp3', audio_list[0], sr)
