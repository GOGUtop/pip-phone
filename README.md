# SillyTavern Native PiP v1.3.0

这个版本把 **PiP 的生命周期完全移到 iPhone 原生 App**，不再依赖 SillyTavern 网页里的 PiP 按钮。

## v1.3.0 主要变化

- 删除旧版 **300 秒 / 5 分钟自动关闭 PiP** 的逻辑。
- App 打开后会自动准备并尝试启动原生 `AVPictureInPictureController`。
- `canStartPictureInPictureAutomaticallyFromInline = true`：切到后台时持续保持 PiP 自动启动能力。
- PiP 被系统临时停止后，不再销毁 `AVPlayer` / `AVPictureInPictureController`，而是继续保持播放器并自动重新待命。
- App 回到前台、准备进入后台、已经进入后台时都会重新检查 PiP 状态。
- PiP 使用 App 内置 `Resources/pip-loop.mp4`，因此不再需要前端扩展给 PiP 提供视频 URL。
- 原来的通知桥、后台音频会话和 SillyTavern 地址保持不变。

默认 SillyTavern 地址：

`http://aaa.xixisillytavern.top:8001/`

## GitHub Actions

上传仓库后：

1. Actions → **Build iPhone IPA**
2. Run workflow
3. 日志确认：`WORKFLOW_VERSION=v1.3.0-INLINE`
4. 下载 Artifact 里的 `SillyTavernNativePiP-unsigned.ipa`
5. 用 SideStore / Sideloadly / AltStore 签名安装

## 关于“常驻 PiP”

App 会尽量持续保持 PiP，并移除了我们自己造成的 5 分钟超时。如果 iOS 因系统资源、用户手动关闭 PiP、播放器中断等原因终止系统 PiP 窗口，App 无法绕过系统强制规则；v1.3 会保留播放器并在可再次启动时自动重试，回到 App 后也会重新启动/待命。

## SillyTavern 扩展

PiP 已经不需要网页扩展控制。配套 `SillyTavernExtension-v3.2.0` 只继续负责：

- 回复开始/结束事件
- WebView 生成期间后台保活
- 回复完成系统通知桥接
- 非原生 App 环境下的网页 PiP 降级

后续可用 SillyTavern Server Plugin 替代这部分前端扩展，从服务器直接处理回复完成事件和推送。
