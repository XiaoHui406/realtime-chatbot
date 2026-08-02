# FFmpeg 安装指南

本项目的参考音频上传预处理依赖 **FFmpeg**：当 `torchaudio` 无法加载上传的音频（如某些编码格式、视频文件中的音轨）时，会回退调用 `ffmpeg` 提取并转换音频流（见 `utils/audio_utils.py`）。

因此，**运行本项目前需要先安装 FFmpeg，并确保 `ffmpeg` 命令在系统 PATH 中可用**。

## 验证是否已安装

在命令行中执行：

```bash
ffmpeg -version
```

如果能正常输出版本信息，说明 FFmpeg 已安装，可跳过下面的安装步骤。

## Windows

### 方式一：winget（推荐）

```powershell
winget install Gyan.FFmpeg
```

安装完成后，需要**重新打开**终端使 PATH 生效。

### 方式二：手动下载

1. 前往 [https://www.gyan.dev/ffmpeg/builds/](https://www.gyan.dev/ffmpeg/builds/)，下载 `ffmpeg-release-essentials.zip`（或从 [FFmpeg 官网](https://ffmpeg.org/download.html) 下载 Windows 构建版本）
2. 解压到一个固定目录，例如 `C:\ffmpeg`，目录结构为 `C:\ffmpeg\bin\ffmpeg.exe`
3. 将 `C:\ffmpeg\bin` 添加到系统 PATH：
   - 打开「设置 → 系统 → 关于 → 高级系统设置 → 环境变量」
   - 在「用户变量」或「系统变量」中找到 `Path`，点击「编辑」，新增一行 `C:\ffmpeg\bin`
   - 点击「确定」保存，并**重新打开**终端
4. 重新执行 `ffmpeg -version` 验证

## macOS

### 方式一：Homebrew（推荐）

```bash
brew install ffmpeg
```

### 方式二：下载静态构建版

从 [https://evermeet.cx/ffmpeg/](https://evermeet.cx/ffmpeg/) 下载，解压后放入某个目录，并将该目录加入 PATH。

## Linux (Ubuntu / Debian)

```bash
sudo apt update
sudo apt install ffmpeg
```

其他发行版（如 CentOS / Fedora / Arch）可参考系统包管理器安装 `ffmpeg` 包。

## Docker

如果使用 Docker 部署，可在 Dockerfile 中安装：

```dockerfile
RUN apt-get update && apt-get install -y ffmpeg
```

## 验证安装

安装完成后，重新打开终端，执行：

```bash
ffmpeg -version
```

看到版本信息即表示安装成功。
