# Real-time Chatbot

基于 WebSocket 的实时 AI 语音聊天机器人，支持语音输入，后端完成 VAD → ASR → LLM → TTS 全链路处理，并将合成语音实时推送回客户端播放。

## Architecture / 架构

```
┌──────────────────┐     WebSocket    ┌─────────────────────────────────────┐
│   Flutter App    │ ◄──────────────► │         Python Backend              │
│  (Microphone)    │   audio bytes    │                                     │
│  (Speaker)       │   ←→ PCM audio   │  VAD (Silero) → ASR  (SenseVoice)   │
│                  │                  │       → LLM (OpenAI API)            │
│                  │                  │       → TTS (Qwen3-TTS + cloning)   │
└──────────────────┘                  └─────────────────────────────────────┘
```

### Pipeline / 处理流程

1. **VAD** — Silero VAD 检测语音活动，自动切分说话片段
2. **ASR** — SenseVoice / Whisper 将语音转为文本
3. **LLM** — 大模型 (OpenAI 兼容 API) 流式生成回复，按标点智能分句
4. **TTS** — Qwen3-TTS 将每句文本合成语音，支持音色克隆

从结束说话到开始播放音频之间的延迟约为2s

## Tech Stack / 技术栈

| 模块     | 技术                                      |
| -------- | ----------------------------------------- |
| 后端框架 | FastAPI + Uvicorn                         |
| VAD      | Silero VAD                                |
| ASR      | FunASR (SenseVoiceSmall) / Faster-Whisper |
| LLM      | OpenAI-compatible API                     |
| TTS      | Qwen3-TTS 12Hz 0.6B                       |
| 客户端   | Flutter                                   |
| 包管理   | uv (Python), pub (Flutter)                |

## Prerequisites / 环境要求

- Python >= 3.12
- Flutter SDK >= 3.10.1 (运行客户端时)
- 显存(VRAM) >= 6GB

## PyTorch (CUDA) / PyTorch 配置

本项目**仅支持 CUDA 版 PyTorch**（不支持 CPU-only 版本）。`pyproject.toml` 默认配置为 **CUDA 12.6**，你需要确保你的电脑有 **显存 >= 6GB** 的 NVIDIA 显卡，并根据你电脑的 CUDA 版本修改配置。

### 1. 查看 CUDA 版本

在命令行中输入以下命令

```bash
nvidia-smi
```

输出右上角会显示 CUDA 版本（如 `CUDA Version: 12.6`）。

### 2. 修改 `pyproject.toml`

根据你的 CUDA 版本，将 `pyproject.toml` 中的 `cu126` 替换为对应的版本标签：

| CUDA 版本 | PyTorch 标签 |
| --------- | ------------ |
| 11.8      | `cu118`      |
| 12.1      | `cu121`      |
| 12.4      | `cu124`      |
| 12.6      | `cu126`      |

涉及以下 4 处修改，以 CUDA 12.4 为例：

```toml
[tool.uv.sources]
torch = [
  { index = "pytorch-cu124", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]
torchaudio = [
  { index = "pytorch-cu124", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]

[[tool.uv.index]]
name = "pytorch-cu124"
url = "https://download.pytorch.org/whl/cu124"
explicit = true
```

> **注意：** PyTorch 的 CUDA 版本是向前兼容的，例如 CUDA 12.6 驱动通常可以运行 `cu124` 版本。如无特殊需求，使用你驱动支持的最高版本即可。

## Quick Start / 快速开始

### 1. Backend / 后端

```bash
# 克隆仓库
git clone <repo-url>
cd realtime-chatbot

# 安装依赖 (推荐使用 uv)
uv sync

# 配置环境变量
# 编辑 .env 文件，填入你的 API Key
```

**.env** 文件示例:

```env
API_KEY=sk-your-deepseek-api-key
BASE_URL=https://api.deepseek.com
MODEL=deepseek-v4-flash
```

**启动后端:**

```bash
python main.py
# 或: uv run main.py
```

服务启动于 `http://127.0.0.1:8000`，WebSocket 端点为 `ws://127.0.0.1:8000/realtime-chat`。

### 2. Flutter Client / 客户端

```bash
cd app
flutter pub get
flutter run
```

## Project Structure / 项目结构

```
realtime-chatbot/
├── main.py                     # 后端入口，WebSocket 服务
├── pyproject.toml              # Python 项目配置
├── .env                        # API 密钥配置
├── service/
│   ├── asr/
│   │   ├── interface/asr_service.py      # ASR 抽象接口
│   │   ├── sensevoice_service.py         # SenseVoice 实现
│   │   └── whisper_service.py            # Whisper 实现
│   ├── chatbot/
│   │   ├── interface/chatbot_service.py  # Chatbot 抽象接口
│   │   └── llm_api_service.py            # LLM API 实现
│   └── tts/
│       ├── interface/tts_service.py      # TTS 抽象接口
│       └── qwen_tts_service.py           # Qwen3-TTS 实现
├── utils/
│   └── agent_tool_manager.py    # Function Calling 工具管理器
├── app/                         # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── pages/chat_page.dart
│   │   └── services/
│   │       ├── ws_service.dart
│   │       ├── audio_recorder.dart
│   │       └── audio_player.dart
│   └── pubspec.yaml
├── audio/
│   └── ref_audio.wav            # 音色克隆参考音频
└── LICENSE                      # MIT License
```

## Configuration / 配置说明

| 配置项       | 文件                  | 说明                                 |
| ------------ | --------------------- | ------------------------------------ |
| LLM API Key  | `.env`                | DeepSeek 或其他 OpenAI 兼容 API 密钥 |
| LLM Model    | `.env`                | 模型名称，默认 `deepseek-v4-flash`   |
| 参考音频     | `audio/ref_audio.wav` | TTS 音色克隆的参考人声               |
| 采样率       | `main.py`             | 默认 16000 Hz                        |
| VAD 合并间隔 | `main.py`             | `MAX_SEGMENT_GAP` 默认 0.5s          |

## License

MIT License. See [LICENSE](LICENSE) for details.
