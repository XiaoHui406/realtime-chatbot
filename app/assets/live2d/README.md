# Live2D Assets Setup

`dist/` 目录由 Cubism SDK for Web 的 Demo 项目编译生成，**不在 Git 仓库中**（已 gitignore）。

## 编译步骤

### 1. 下载 Cubism SDK for Web

https://www.live2d.com/en/sdk/download/web/

解压到任意位置，例如 `E:\CubismSdkForWeb-5-r.5`。

### 2. 安装依赖并编译

```powershell
cd CubismSdkForWeb-5-r.5\Samples\TypeScript\Demo
npm install
node copy_resources.js
npx vite build --mode development
```

### 3. 复制到项目

```powershell
Remove-Item -Recurse -Force app\assets\live2d\dist
Copy-Item -Recurse CubismSdkForWeb-5-r.5\Samples\TypeScript\Demo\dist\* app\assets\live2d\dist\
```

### 4. 验证

```powershell
cd app\assets\live2d\dist
python -m http.server 8080
```

浏览器打开 `http://localhost:8080` 应能看到 Hiyori 模型。

## 最终目录结构

```
assets/live2d/
├── README.md
└── dist/                    ← 🔒 编译产物 (已 gitignore)
    ├── index.html
    ├── assets/
    │   └── index-*.js
    ├── Core/
    │   └── live2dcubismcore.js
    ├── Framework/
    │   └── Shaders/
    └── Resources/
        └── Hiyori/          ← 模型文件
```

## 源码修改说明

Demo 源码已做以下修改（修改后的文件位于 SDK 目录中）：

- `lappdefine.ts`: 只加载 Hiyori 模型，关闭调试日志
- `lappview.ts`: 移除齿轮图标和背景图片
- `lappdelegate.ts`: 暴露 `getLive2DManager()` 方法
- `lapplive2dmanager.ts`: 增加参数覆盖机制，暴露参数和表情控制接口
- `main.ts`: 增加 `Live2DBridge` 全局 API（嘴型、眼睛、表情、动作控制）
- `index.html`: 增加状态栏 UI，透明背景
