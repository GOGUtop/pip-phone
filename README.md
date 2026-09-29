# SillyTavern Native PiP iOS Shell v1.4.0

这是配套 `st-native-monitor` SillyTavern Server Plugin 的 iPhone 原生壳。

## v1.4.0 重点

旧版完成提醒依赖 WKWebView 前端的 `generation_ended`。iOS 在后台可能冻结 WebContent/JavaScript，所以会出现“模型早就跑完，但只有重新点开 App 才响和弹横幅”。

v1.4.0 新增 `ServerMonitor.swift`：

- 原生 App 使用 URLSession 每约 1.5 秒读取 `/api/plugins/st-native-monitor/status`。
- App 内置一个真正的无声原生 MP3 循环，并使用 `AVAudioSession.playback + mixWithOthers`，用于尽量让原生监测器在后台继续运行；它不会主动暂停其他 App 的声音。
- 轮询发生在 Swift 原生进程，不依赖 WKWebView JavaScript。
- Server Plugin 在 SillyTavern 服务器端观察生成请求真正结束。
- 服务器状态变为 `done` 后，Swift 直接通过 `UNUserNotificationCenter` 发系统横幅和系统声音。
- 原生 PiP 常驻逻辑仍保留，不再有 5 分钟自动停止。

## 必须同时安装

1. iOS App v1.4.0（本工程编译出的 IPA）
2. 前端扩展 `原生通知桥接 v3.3.0`
3. Server Plugin `st-native-monitor v1.0.0`

缺少 Server Plugin 时仍会回退到旧的前端 `generation_ended` 提醒，因此后台延迟问题仍可能出现。

## 默认地址

`http://aaa.xixisillytavern.top:8001/`

GitHub Actions 运行时仍可以修改 `start_url`。

## GitHub Actions

仓库根目录上传：

- `.github/`
- `SillyTavernNativePiP/`
- `SillyTavernNativePiP.xcodeproj/`
- README 文件

运行：`Actions -> Build iPhone IPA -> Run workflow`

日志应出现：

`WORKFLOW_VERSION=v1.4.0-INLINE`

产物：`SillyTavernNativePiP-unsigned.ipa`

未签名 IPA 仍需 SideStore / AltStore / Sideloadly 等签名后安装。

## 后台通知原理

生成请求由前端扩展改道到：

`/api/plugins/st-native-monitor/proxy`

Server Plugin 再转发到 SillyTavern 原始生成端点，并只保存生成状态，不保存提示词和回复正文。对于工具调用等连续请求，插件会等待约 1.8 秒“安静窗口”后才判定整个回合结束，以减少过早通知。

## 当前支持的生成后端

Server Plugin v1.0.0 监测：

- Chat Completion
- Text Completion
- Kobold
- NovelAI

Horde 暂未纳入服务端完成检测，因为它是“提交任务 + 独立状态轮询”模型，不能用初始 HTTP 请求结束作为生成结束。

> 注意：这是侧载场景下的后台保活设计，会比纯网页更耗电。用户强制划掉 App、系统终止 App 或关闭后台媒体后，必须使用 APNs 才能做到完全独立于 App 存活的远程推送。
