# Live2D WebView 前端

基于 Cubism SDK for Web 5-r.5 官方 Demo 构建的 Live2D 渲染层，运行在 Flutter WebView 中。

## 前置条件

### 1. 下载 Cubism SDK for Web

从 [Live2D 官网](https://www.live2d.com/download/cubism-sdk/) 下载 **Cubism SDK for Web**，将解压后的整个目录放置于此：

```
assets/live2d/CubismSdkForWeb-5-r.5/
├── Core/                    # 引擎核心（专有许可）
├── Framework/               # TypeScript 框架（开放许可）
├── Samples/                 # 示例项目（开放许可）
├── LICENSE.md               # 许可证说明
├── NOTICE.md                # 第三方声明
└── ...
```

### 2. 安装 Node.js 依赖

```bash
cd app/assets/live2d
npm install
```

## 构建

```bash
npm run build
```

构建产物输出到 `dist/` 目录：

```
dist/
├── index.html                    # WebView 入口
├── Core/                         # Cubism Core JS (live2dcubismcore.js)
├── Framework/Shaders/WebGL/      # WebGL2 shader 文件
└── assets/index.js               # 编译后的应用 JS
```

> **注意**：如果此前在未安装 SDK 的情况下运行过 Flutter，Flutter 可能缓存了不含 SDK 的旧资源清单。首次构建完成后务必执行 `flutter clean` 再 `flutter run`，否则应用无法检测到 Live2D。

### 缓存清理

首次运行 Flutter 应用时，`dist/` 文件会被缓存到应用数据目录。重新构建 `dist/` 后，需清理缓存才能生效：

**Windows**：
```powershell
Remove-Item -Recurse -Force "$env:APPDATA\com.example\app\live2d"
```

**Android**：
```bash
adb shell run-as com.example.app rm -r /data/data/com.example.app/files/live2d
```

## 使用其他版本的 SDK

本项目默认面向 **Cubism SDK for Web 5-r.5**。若使用不同版本，需修改以下文件中出现的版本号（假设新版本目录名为 `CubismSdkForWeb-6-r.1`）：

| 文件 | 路径 | 修改内容 |
|------|------|---------|
| `tsconfig.json` | `paths` 和 `include` | `CubismSdkForWeb-5-r.5` → 新目录名 |
| `vite.config.mts` | `sdkPath` 变量 | `CubismSdkForWeb-5-r.5` → 新目录名 |
| `copy_resources.js` | `sdkPath` 变量 | `CubismSdkForWeb-5-r.5` → 新目录名 |
| `.gitignore`（根目录 + `app/` 两处） | ignore 规则 | `CubismSdkForWeb-5-r.5` → 新目录名 |

以上任一路径配置错误会导致构建失败（模块找不到）。其余文件（`src/` 下的 TS 源码、`pubspec.yaml`、`live2d_server.dart`）与 SDK 版本无关，无需修改。

## 许可证

本模块基于官方 Demo 修改而来，依赖以下 Live2D 组件：

| 组件 | 许可 | 说明 |
|------|------|------|
| **Cubism Core** (`live2dcubismcore.js`) | [专有软件许可](https://www.live2d.com/eula/live2d-proprietary-software-license-agreement_en.html) | 不可修改分发，由 SDK 原样提供 |
| **Framework** | [开放软件许可](https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html) | 允许修改和商用 |
| **Samples** | 同上 | Demo 代码可自由修改使用 |
| **示例模型** (Haru, Mao 等) | [免费素材许可](https://www.live2d.com/eula/live2d-free-material-license-agreement_en.html) | 仅限集成到应用中展示，不可单独再分发 |

**商业使用注意事项**：年销售额超过 1000 万日元的企业需另行获取 [Cubism SDK 发布许可](https://www.live2d.com/en/download/cubism-sdk/release-license/)。

完整的许可证文本参见 SDK 目录下的 `LICENSE.md`、`NOTICE.md` 及各组件根目录下的相关文件。

## Live2DBridge API

| 方法 | 参数 | 说明 |
|------|------|------|
| `isReady()` | - | 模型是否加载完成，返回 `boolean` |
| `setMouthOpen(v)` | `number` 0~1 | 设置口型开合度 |
| `setEyeOpen(v)` | `number` 0~1 | 设置眼睛开合度 |
| `setExpression(name)` | `string` | 播放表情（名称来自模型定义） |
| `startMotion(group, index)` | `string`, `number` | 播放动作 |
| `switchModel(path)` | `string` | 切换模型，传入模型目录路径 |
| `getExpressionNames()` | - | 获取可用表情名列表 |
| `getMotionGroups()` | - | 获取可用动作组列表 |
