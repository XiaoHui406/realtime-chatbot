# Real-time Chatbot

基于 WebSocket 的实时 AI 语音聊天机器人，支持语音输入，后端完成 VAD → ASR → LLM → TTS 全链路处理，并将合成语音实时推送回客户端播放。支持多会话管理、TTS 音色克隆、Function Calling / MCP 工具调用。

**客户端平台支持**：Android / iOS / macOS / Windows 桌面端，其中 **Android 和 Windows 已经过实际测试**，iOS / macOS 理论可用但未经验证。

## Architecture / 架构

```
┌──────────────────┐     WebSocket    ┌──────────────────────────────────────────────┐
│   Flutter App    │ ◄──────────────► │              Python Backend                  │
│  (Microphone)    │   audio bytes    │                                              │
│  (Speaker)       │   ←→ PCM audio   │  VAD (Silero) → ASR  (SenseVoice)            │
│  (会话管理 UI)    │                  │       → LLM (OpenAI API) ←→ MCP Servers      │
│                  │    REST API      │       → TTS (Qwen3-TTS + cloning)            │
│                  │ ◄──────────────► │  会话/消息持久化 (SQLite)                     │
└──────────────────┘                  └──────────────────────────────────────────────┘
```

### Pipeline / 处理流程

1. **VAD** — Silero VAD 全程流式检测，静音超过 `MIN_SILENCE_DURATION_MS`(默认 200ms) 视为一句话结束，短停顿自动合并
2. **ASR** — SenseVoice / Whisper 将语音转为文本
3. **LLM** — 大模型 (OpenAI 兼容 API) 流式生成回复，按标点智能分句（首句激进切分以尽早发声），回复内容与会话绑定持久化
4. **TTS** — Qwen3-TTS 将每句文本合成语音，支持音色克隆；送入 TTS 前自动清理 markdown 标记与 emoji

**延迟参考**：在 RTX 3060 Laptop (6GB) + i7-12700H + 32GB RAM 配置下，从结束说话到开始播放音频的延迟约为 2s（内置 `latency_tracer` 打点工具，控制台输出各阶段耗时）

## Tech Stack / 技术栈

| 模块     | 技术                                                                  |
| -------- | --------------------------------------------------------------------- |
| 后端框架 | FastAPI + Uvicorn                                                     |
| VAD      | Silero VAD                                                            |
| ASR      | FunASR (SenseVoiceSmall) / Faster-Whisper                             |
| LLM      | OpenAI-compatible API                                                 |
| TTS      | Qwen3-TTS 12Hz 0.6B                                                   |
| 工具调用 | Function Calling + MCP (Model Context Protocol)                       |
| 数据库   | SQLite + SQLAlchemy (async)                                           |
| 客户端   | Flutter（Android / iOS / macOS / Windows，Android 与 Windows 已实测） |
| 音频收发 | record (录音) / flutter_soloud (低延迟流式播放)                       |
| 包管理   | uv (Python), pub (Flutter)                                            |

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

## Authentication / 接口鉴权

在 `.env` 中配置 `AUTH_API_KEY` 后启用鉴权（留空则跳过验证）：

- **REST API**：请求头携带 `Authorization: Bearer <AUTH_API_KEY>`
- **WebSocket**：握手时同样携带 `Authorization: Bearer <AUTH_API_KEY>` 请求头
- **客户端**：在 App 的设置页填入 API Key，自动附加到所有请求

## Realtime Chat / 实时语音通话

WebSocket 端点：`ws://host:port/realtime-chat?session_id=<会话id>`（鉴权通过 `Authorization` 请求头）

- 客户端持续推送 **16kHz / 16bit / 单声道** PCM 音频（每块 1024 字节）
- 后端推送 **24kHz float32** PCM 音频块，客户端流式播放
- 发送文本 `exit` 主动结束通话
- 通话期间 LLM 可通过 websocket 向客户端发起反向请求（如 `get_location` 获取定位），客户端以 JSON 应答

## Session Management / 会话管理

对话与消息按会话持久化到 SQLite，新会话自动写入面向语音场景的系统提示词（纯文本、单段落、禁用 markdown），也可在创建时附加自定义 `initial_prompt`。

| 方法   | 路径                                     | 参数                      | 说明                           |
| ------ | ---------------------------------------- | ------------------------- | ------------------------------ |
| GET    | `/chatbot_session`                       | `limit`, `offset`         | 获取会话列表（按更新时间倒序） |
| POST   | `/chatbot_session`                       | `title`, `initial_prompt` | 创建会话                       |
| PUT    | `/chatbot_session/{session_id}`          | `title`                   | 重命名会话                     |
| GET    | `/chatbot_session/{session_id}/messages` | —                         | 获取会话消息记录               |
| DELETE | `/chatbot_session/{session_id}`          | —                         | 删除会话                       |

## Reference Audio / 参考音频管理

参考音频用于 TTS 音色克隆。系统支持上传、查看、编辑、设定和删除参考音频。

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

| 方法   | 路径                                   | 参数                           | 说明                        |
| ------ | -------------------------------------- | ------------------------------ | --------------------------- |
| POST   | `/reference_audio`                     | `audio` (文件), `name`, `tags` | 上传参考音频                |
| GET    | `/reference_audio`                     | —                              | 获取所有参考音频列表        |
| PUT    | `/reference_audio/{audio_id}/activate` | —                              | 设定当前 TTS 使用的参考音频 |
| PUT    | `/reference_audio/{audio_id}`          | `name`, `tags`                 | 编辑参考音频信息            |
| DELETE | `/reference_audio/{audio_id}`          | —                              | 删除指定参考音频及对应文件  |

### 使用示例

```bash
# 上传参考音频
curl -X POST "http://127.0.0.1:8000/reference_audio?name=我的声音&tags=中文,男声" \
  -H "Authorization: Bearer your-auth-api-key" \
  -F "audio=@your_voice.wav"

# 查看所有参考音频
curl "http://127.0.0.1:8000/reference_audio" \
  -H "Authorization: Bearer your-auth-api-key"

# 设定参考音频
curl -X PUT "http://127.0.0.1:8000/reference_audio/1/activate" \
  -H "Authorization: Bearer your-auth-api-key"

# 删除参考音频
curl -X DELETE "http://127.0.0.1:8000/reference_audio/1" \
  -H "Authorization: Bearer your-auth-api-key"
```

## Function Calling & MCP / 工具调用与 MCP 集成

LLM 支持通过 Function Calling 调用外部工具，工具来源分为两类：**本地工具**（Python 函数通过装饰器注册）和 **MCP 工具**（通过 Model Context Protocol 连接外部 MCP 服务器）。

所有工具管理器实现 `ToolManager` 协议（`utils/tool_call/interface/tool_manager.py`），`ToolManagerProxy` 在启动时汇总所有管理器的工具列表并统一分派调用。

### MCP 服务器配置

MCP 服务器通过 `config.json` 配置，支持**本地服务器**和**远程服务器**两种类型。

#### 配置结构

```json
{
    "mcp": {
        "<server-name>": {
            "type": "local",
            "command": ["npx", "-y", "@scope/mcp-server@latest"]
        },
        "<server-name>": {
            "type": "remote",
            "url": "https://your.mcp.server"
        }
    }
}
```

每个 MCP 服务器的 key 为自定义名称，其工具在 LLM 中会以 `<server-name>_<tool-name>` 格式命名，避免冲突。

#### 本地服务器 (type: local)

适用于 npm 包、Python 脚本等本地进程，服务启动时自动拉起子进程并通过标准输入/输出通信。

```json
{
    "mcp": {
        "local-server": {
            "type": "local",
            "command": ["npx", "-y", "@scope/mcp-server@latest"],
            "enabled": true,
            "timeout": 5000,
            "environment": { "API_KEY": "xxx" }
        }
    }
}
```

| 字段          | 类型        | 说明                             |
| ------------- | ----------- | -------------------------------- |
| `type`        | `"local"`   | 固定值                           |
| `command`     | `list[str]` | 启动命令，第一个元素为可执行文件 |
| `enabled`     | `bool`      | 是否启用，默认 `true`            |
| `timeout`     | `int`       | 超时时间（毫秒），默认 `5000`    |
| `environment` | `dict`      | 子进程环境变量，可选             |

#### 远程服务器 (type: remote)

适用于远程 HTTP MCP 服务，支持 **Streamable HTTP** 和 **SSE** 两种传输协议，连接失败会自动回退。

```json
{
    "mcp": {
        "remote-server": {
            "type": "remote",
            "url": "https://mcp.example.com",
            "enabled": true,
            "timeout": 5000,
            "headers": { "Authorization": "Bearer xxx" }
        }
    }
}
```

| 字段      | 类型       | 说明                          |
| --------- | ---------- | ----------------------------- |
| `type`    | `"remote"` | 固定值                        |
| `url`     | `str`      | 远程 MCP 服务 URL             |
| `enabled` | `bool`     | 是否启用，默认 `true`         |
| `timeout` | `int`      | 超时时间（毫秒），默认 `5000` |
| `headers` | `dict`     | 自定义 HTTP 请求头，可选      |

> 参考 `config.example.json` 创建 `config.json`，该文件已被 `.gitignore` 忽略。

### 本地工具注册

所有本地工具模块放置在 `utils/tool_call/tools/` 目录下，服务启动时 `tool_manager_registry.py` 会自动扫描并加载。编写新工具只需两步：

1. 在 `utils/tool_call/tools/` 下新建一个 `.py` 文件
2. 使用 `@agent_tool_manager.agent_tool()` 装饰器注册函数

### 编写工具的两种方式

**方式一：自动生成参数模型（推荐）** — 装饰器不带参数，根据函数类型注解自动生成 Pydantic 模型：

```python
from utils.tool_call.tool_manager_registry import agent_tool_manager

@agent_tool_manager.agent_tool()
async def weather_search(city: str):
    """输入城市名称，返回城市天气信息"""
    # 你的工具逻辑
    ...
```

**方式二：手动指定参数模型** — 适合需要参数校验或复杂嵌套结构的场景：

```python
from pydantic import BaseModel, Field
from utils.tool_call.tool_manager_registry import agent_tool_manager

class WebSearchParams(BaseModel):
    content: str = Field(description='搜索内容')
    search_count: int = Field(description='搜索数量', default=5)

@agent_tool_manager.agent_tool(InputClass=WebSearchParams)
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

| 工具             | 文件                                      | 功能         | 依赖                                    |
| ---------------- | ----------------------------------------- | ------------ | --------------------------------------- |
| `web_search`     | `utils/tool_call/tools/web_search.py`     | 智谱联网搜索 | 需在 `.env` 中配置 `ZAI_API_KEY`        |
| `weather_search` | `utils/tool_call/tools/weather_search.py` | 城市天气查询 | 无                                      |
| `get_location`   | `utils/tool_call/tools/get_location.py`   | 获取用户定位 | 通过 websocket 向客户端请求，需通话在线 |

## Quick Start / 快速开始

### 1. Backend / 后端

```bash
# 克隆仓库
git clone https://github.com/XiaoHui406/realtime-chatbot.git
cd realtime-chatbot

# 安装依赖 (推荐使用 uv)
uv sync

# 配置环境变量
# 参考 .env.example 创建 .env 文件，填入你的 API Key
```

**.env** 文件示例:

```env
API_KEY=sk-your-deepseek-api-key
BASE_URL=https://api.deepseek.com
MODEL=deepseek-v4-flash

# API Key 鉴权，留空则跳过验证
AUTH_API_KEY=

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

# Android
flutter run

# Windows 桌面端
flutter run -d windows
```

> 服务器地址在 `app/lib/services/config.dart` 中配置（默认 `127.0.0.1:8000`），API Key 可在 App 设置页填写。

## Project Structure / 项目结构

```
realtime-chatbot/
├── main.py                        # 后端入口：WebSocket 实时通话 & FastAPI lifespan & 鉴权中间件
├── service_registry.py            # 全局服务注册（VAD/ASR/LLM/TTS/客户端请求管理器）
├── database_engine.py             # 数据库引擎配置
├── config.example.json            # MCP 配置模板
├── pyproject.toml                 # Python 项目配置
├── .env.example                   # 环境变量模板
├── router/
│   ├── chatbot_session_router.py  # 会话管理 REST API
│   └── reference_audio_router.py  # 参考音频 REST API
├── service/
│   ├── asr/
│   │   ├── interface/asr_service.py      # ASR 抽象接口
│   │   ├── sensevoice_service.py         # SenseVoice 实现
│   │   └── whisper_service.py            # Whisper 实现
│   ├── chatbot/
│   │   ├── interface/chatbot_service.py  # Chatbot 抽象接口
│   │   └── llm_api_service.py            # LLM API 实现（Function Calling + 消息持久化）
│   └── tts/
│       ├── interface/tts_service.py      # TTS 抽象接口
│       └── qwen_tts_service.py           # Qwen3-TTS 实现
├── model/
│   ├── chatbot_session.py         # 会话/消息/工具调用 数据库模型 & API 模型
│   ├── reference_audio.py         # 参考音频 数据库模型 & API 响应模型
│   └── mcp_model.py               # MCP 服务器配置模型
├── utils/
│   ├── audio_utils.py             # 音频预处理 (格式转换/重采样/单声道)
│   ├── auth.py                    # AUTH_API_KEY 读取
│   ├── chatbot_session_utils.py   # 会话消息加载
│   ├── client_request_manager.py  # 服务端→客户端反向请求（如获取定位）
│   ├── latency_tracer.py          # 延迟打点工具
│   ├── text_sanitizer.py          # markdown/emoji 清理（入库与 TTS 前）
│   └── tool_call/                 # 工具调用模块
│       ├── interface/
│       │   └── tool_manager.py    # ToolManager 协议
│       ├── agent_tool_manager.py  # 本地工具管理器
│       ├── mcp_tool_manager.py    # MCP 工具管理器
│       ├── tool_manager_proxy.py  # 工具管理器代理（汇总+MCP工具分派）
│       ├── tool_manager_registry.py # 工具管理器注册与初始化
│       └── tools/
│           ├── web_search.py      # 联网搜索工具
│           ├── weather_search.py  # 天气查询工具
│           └── get_location.py    # 位置获取工具
├── app/                           # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── pages/
│   │   │   ├── session_list_page.dart    # 会话列表
│   │   │   ├── chat_detail_page.dart     # 会话消息记录
│   │   │   ├── call_page.dart            # 实时语音通话
│   │   │   ├── reference_audio_page.dart # 参考音频管理
│   │   │   └── settings_page.dart        # 设置（API Key）
│   │   └── services/
│   │       ├── api_service.dart          # REST API 封装
│   │       ├── ws_service.dart           # WebSocket 封装
│   │       ├── audio_recorder.dart       # 录音 (record)
│   │       ├── audio_player.dart         # 流式播放 (flutter_soloud)
│   │       ├── settings_service.dart     # 本地设置存储
│   │       ├── config.dart               # 服务器地址配置
│   │       └── wav_utils.dart            # PCM/WAV 工具
│   └── pubspec.yaml
├── audio/                         # 参考音频存储目录
└── LICENSE                        # MIT License
```

## Configuration / 配置说明

| 配置项       | 文件                           | 说明                                             |
| ------------ | ------------------------------ | ------------------------------------------------ |
| LLM API Key  | `.env`                         | DeepSeek 或其他 OpenAI 兼容 API 密钥             |
| LLM Model    | `.env`                         | 模型名称，默认 `deepseek-v4-flash`               |
| 接口鉴权     | `.env`                         | `AUTH_API_KEY`，留空则关闭鉴权                   |
| MCP 服务器   | `config.json`                  | MCP 服务器连接配置（参考 `config.example.json`） |
| 采样率       | `main.py`                      | 默认 16000 Hz，上传音频自动重采样                |
| 端点静音时长 | `main.py`                      | `MIN_SILENCE_DURATION_MS` 默认 200ms             |
| 静音保护     | `main.py`                      | `IDLE_BUFFER_MAX_S` / `IDLE_BUFFER_KEEP_S`       |
| 服务器地址   | `app/lib/services/config.dart` | 客户端连接的后端地址                             |

## License

MIT License. See [LICENSE](LICENSE) for details.
