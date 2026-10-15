# 雨爱 · RainASCII for macOS

在 macOS Terminal 中播放《新宿决战 · 雨爱》黑白 ASCII 字符动画，带本地音轨、约 3 秒乱码开场、窗口自适应与自动跳帧。正片约 110 秒，24 fps。

## 来源与致谢

本项目灵感来自 B 站视频 [《输入一串乱码就可以用cmd播放新宿决战!》](https://www.bilibili.com/video/BV1sfp869EUH/)，UP 主：゙゙゙茶呆呆。

作为移植基础的 Windows 项目，是从上述视频下方提供的网盘链接下载的。本项目基于该下载项目制作 macOS 版本：参考其中 `Player.cs` 的交互与 ASCII 渲染方式，使用 Swift、Darwin 与 AVFoundation 重新实现播放器，并复用下载项目中的动画帧和音轨。

下载项目内的素材记录另行注明视频为 [《「新宿决战」雨爱版》](https://www.bilibili.com/video/BV1QC3G6DEKX/)，UP 主：望穿秋水145；该信息保留作为素材溯源，未独立核实。

感谢原视频及 Windows 下载项目的创作者。视频、音乐及角色等权利归相应权利人，仅供本地学习体验；本项目不表示获得素材转载许可。本项目直接复用下载包内已有的帧数据，不重新处理原视频。

## 启动

双击 `rainLove.command`，在 Terminal 中运行。也可以在已有终端输入：

```bash
cd ~/Documents/RainASCII
./rainLove.command
./rainLove.command --mute
./rainLove.command --no-intro
./rainLove.command --duration 10
```

Q、Esc 或 Ctrl+C 退出，结束时恢复原终端屏幕、光标和输入状态。窗口需要获得焦点才能接收按键。Ctrl+Z 在播放期间忽略，避免挂起后留下隐藏光标或关闭回显的终端。

放大窗口或缩小等宽字体可以显示更多细节。画面按比例居中，窗口缩放会自动适配。默认字符宽高比为 0.5；字体导致画面变形时可用 `--cell-aspect 0.45` 调整，允许 0.1 至 2。为限制异常终端尺寸带来的开销，最多绘制 800 列、300 行，末行保留以避免滚屏。ANSI 真彩色效果取决于终端支持。

## 构建和检查

首版面向当前 Mac，已构建程序放在 `bin/rain-ascii`；播放离线运行，无需 Python、第三方运行库或管理员权限。依赖系统 `/usr/bin/gzip`。正常播放使用约 150 MiB 的解压帧数据，加上解码与渲染开销。

重新构建需要 Apple Command Line Tools（`xcrun swiftc`）：

```bash
./scripts/build.sh
./rainLove.command --validate
./rainLove.command --help
```

入口在程序缺失时自动尝试构建。换到其他架构的 Mac 时请重新构建。本机二进制未经 Developer ID 签名或公证，不作为通用 macOS 安装包。支持 macOS 13 及以上版本；最低版本兼容性尚未在旧系统实机验证。

`--validate` 检查 gzip 完整性、文件头、完整帧边界、音频解码及音画时长匹配，不播放声音。`--assets /路径` 可以指定另一套相同格式的素材。缺少或损坏的素材会报告错误，不自动联网补齐；音频设备不可用时可尝试 `--mute`。

## 文件

- `Sources/main.swift`：播放器源码。
- `scripts/build.sh`：本机构建脚本。
- `rainLove.command`：双击／命令行入口。
- `Assets/frames.bin.gz`：YUAI0002 文件头和 320×180 灰度帧。
- `Assets/audio.wav`：已有项目音轨。
- `docs/`：设计、中文实施计划和验证记录。

仅移植播放所需素材。项目不包含关机功能，也不修改 Terminal 设置。按任务要求，未创建或运行单元测试；实现完成后执行构建、完整素材检查及终端集成验证，记录见 `docs/verification.md`。
