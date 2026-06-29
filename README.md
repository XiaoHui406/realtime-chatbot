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

**延迟参考**：在 RTX 3060 Laptop (6GB) + i7-12700H + 32GB RAM 配置下，从结束说话到开始播放音频的延迟约为 2s

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

涉及以下 5 处修改，以 CUDA 12.4 为例：

```toml
[tool.uv.sources]
torch = [
  { index = "pytorch-cu124", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]
torchaudio = [
  { index = "pytorch-cu124", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]
torchcodec = [
  { index = "pytorch-cu124", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]

[[tool.uv.index]]
name = "pytorch-cu124"
url = "https://download.pytorch.org/whl/cu124"
explicit = true
```

> **注意：** PyTorch 的 CUDA 版本是向前兼容的，例如 CUDA 12.6 驱动通常可以运行 `cu124` 版本。如无特殊需求，使用你驱动支持的最高版本即可。

## Reference Audio / 参考音频管理

参考音频用于 TTS 音色克隆。系统支持上传、查看、设定和删除参考音频。

### 数据库模型

| 字段              | 类型     | 说明                 |
| ----------------- | -------- | -------------------- |
| `id`              | int      | 自增主键             |
| `name`            | string   | 音频名称             |
| `file_path`       | string   | 文件存储路径         |
| `transcribe_text` | string   | ASR 识别文本         |
| `tags`            | string   | 标签                 |
| `uploaded_at`     | datetime | 上传时间（自动生成） |

### 上传预处理

上传的音频会经过以下预处理流程：

1. 用 `torchaudio` 加载（支持 WAV / MP3 / FLAC 等格式），失败则回退到 `ffmpeg` 提取音频流
2. 转为单声道（多声道取均值混音）
3. 重采样至 **16kHz**
4. Silero VAD 检测说话片段，取前 3 个有效片段合并
5. ASR 转写为文本存入数据库

音频保存路径为 `./audio/{uuid}.wav`。

### API 接口

| 方法 | 路径                      | 参数                           | 说明                        |
| ---- | ------------------------- | ------------------------------ | --------------------------- |
| POST | `/upload_reference_audio` | `audio` (文件), `name`, `tags` | 上传参考音频                |
| GET  | `/get_reference_audios`   | —                              | 获取所有参考音频列表        |
| GET  | `/set_reference_audio`    | `audio_id`                     | 设定当前 TTS 使用的参考音频 |
| GET  | `/delete_reference_audio` | `audio_id`                     | 删除指定参考音频及对应文件  |

### 使用示例

```bash
# 上传参考音频
curl -X POST "http://127.0.0.1:8000/upload_reference_audio" \
  -F "audio=@your_voice.wav" \
  -F "name=我的声音" \
  -F "tags=中文,男声"

# 查看所有参考音频
curl "http://127.0.0.1:8000/get_reference_audios"

# 设定参考音频
curl "http://127.0.0.1:8000/set_reference_audio?audio_id=1"

# 删除参考音频
curl "http://127.0.0.1:8000/delete_reference_audio?audio_id=1"
```

## Function Calling / 工具调用

LLM 支持通过 Function Calling 调用外部工具（如联网搜索、天气查询等），工具会自动注册并生成 OpenAI 兼容的 JSON Schema。

### 工具注册机制

所有工具模块放置在 `utils/tools/` 目录下，服务启动时 `tool_manager_registry.py` 会自动扫描并加载。编写新工具只需两步：

1. 在 `utils/tools/` 下新建一个 `.py` 文件
2. 使用 `@tool_manager.agent_tool()` 装饰器注册函数

### 编写工具的两种方式

**方式一：自动生成参数模型（推荐）** — 装饰器不带参数，根据函数类型注解自动生成 Pydantic 模型：

```python
from utils.tool_manager_registry import tool_manager

@tool_manager.agent_tool()
async def weather_search(city: str):
    """输入城市名称，返回城市天气信息"""
    # 你的工具逻辑
    ...
```

**方式二：手动指定参数模型** — 适合需要参数校验或复杂嵌套结构的场景：

```python
from pydantic import BaseModel, Field
from utils.tool_manager_registry import tool_manager

class WebSearchParams(BaseModel):
    content: str = Field(description='搜索内容')
    search_count: int = Field(description='搜索数量', default=5)

@tool_manager.agent_tool(InputClass=WebSearchParams)
async def web_search(web_search_params: WebSearchParams):
    """输入搜索内容和搜索数量，返回联网搜索结果"""
    ...
```

> 要点：
>
> - 函数的 `docstring` 会自动作为工具的 `description` 发送给 LLM
> - 返回值需要能被 `json.dumps()` 序列化
> - 支持同步函数和 `async` 函数，管理器会自动适配

### 内置示例工具

| 工具             | 文件                            | 功能         | 依赖                             |
| ---------------- | ------------------------------- | ------------ | -------------------------------- |
| `web_search`     | `utils/tools/web_search.py`     | 智谱联网搜索 | 需在 `.env` 中配置 `ZAI_API_KEY` |
| `weather_search` | `utils/tools/weather_search.py` | 城市天气查询 | 无                               |

## Quick Start / 快速开始

### 1. Backend / 后端

```bash
# 克隆仓库
git clone https://github.com/XiaoHui406/realtime-chatbot.git
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

# 智谱apikey，用于联网搜索工具，可以为空
ZAI_API_KEY=your-zai-api-key
```

**启动后端:**

```bash
uv run main.py
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
├── main.py                     # 后端入口，WebSocket 服务 & REST API
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
├── model/
│   ├── reference_audio.py      # 参考音频 数据库模型 & API 响应模型
│   └── timestamp.py            # 时间戳模型
├── utils/
│   ├── audio_utils.py          # 音频预处理 (格式转换/重采样/单声道)
│   ├── agent_tool_manager.py   # Function Calling 工具管理器
│   └── tools/
│       ├── web_search.py       # 联网搜索工具
│       └── weather_search.py   # 天气查询工具
├── app/                        # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── pages/chat_page.dart
│   │   └── services/
│   │       ├── ws_service.dart
│   │       ├── audio_recorder.dart
│   │       └── audio_player.dart
│   └── pubspec.yaml
├── audio/                      # 参考音频存储目录
├── database_engine.py           # 数据库引擎配置
└── LICENSE                      # MIT License
```

## Configuration / 配置说明

| 配置项       | 文件      | 说明                                 |
| ------------ | --------- | ------------------------------------ |
| LLM API Key  | `.env`    | DeepSeek 或其他 OpenAI 兼容 API 密钥 |
| LLM Model    | `.env`    | 模型名称，默认 `deepseek-v4-flash`   |
| 采样率       | `main.py` | 默认 16000 Hz，上传音频自动重采样    |
| VAD 合并间隔 | `main.py` | `MAX_SEGMENT_GAP` 默认 0.5s          |

## License

MIT License. See [LICENSE](LICENSE) for details.
