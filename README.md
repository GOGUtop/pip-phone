# SillyTavern Native PiP v1.1.2 — GitHub Actions 版

本版在原生 PiP 工程基础上加入了 **GitHub Actions 一键编译 IPA**。

你的 SillyTavern 默认地址已经配置为：

`http://aaa.xixisillytavern.top:8001/`

## 最快使用方式

1. 把本目录所有内容上传到 GitHub 仓库根目录。
2. 打开 **Actions → Build iPhone IPA → Run workflow**。
3. 地址不变就保持默认值，直接运行。
4. 构建变绿后，在该运行页面底部下载 Artifact。
5. 得到 `SillyTavernNativePiP-unsigned.ipa`，用 Sideloadly / SideStore / AltStore 签名安装。

详细步骤见：[`GITHUB_ACTIONS_一键编译.md`](./GITHUB_ACTIONS_一键编译.md)

---

## 原工程说明

# SillyTavern Native PiP for iPhone v1.0.0

这是给 `http://aaa.xixisillytavern.top:8001/` 配好的 iOS 原生壳 + SillyTavern 前端扩展。

## 这版解决什么

- 主屏幕 Web App 的网页 PiP 被 WebKit 限制时，不再走网页 PiP。
- SillyTavern 扩展按钮通过 `window.webkit.messageHandlers.stNative` 调用 Swift。
- Swift 使用 `AVPictureInPictureController + AVPlayerLayer` 创建真正的 iOS 系统画中画。
- 回复完成后，扩展把事件发给 Swift；Swift 使用 `UNUserNotificationCenter` 发系统横幅，并使用系统通知声音。
- App 在前台时也会显示横幅（`UNUserNotificationCenterDelegate` 的 `willPresent` 已处理）。
- App 配置了 `UIBackgroundModes = audio`，用于 Audio/AirPlay/Picture in Picture 后台媒体能力。

## 文件

- `SillyTavernNativePiP.xcodeproj`：直接用 Xcode 打开。
- `SillyTavernNativePiP/`：Swift 源码。
- `sillytavern-native-pip-extension-v3.0.0.zip`：SillyTavern 前端扩展。
- `SillyTavernExtension-v3.0.0/`：扩展源码。

## 第一步：替换 SillyTavern 扩展

1. 删除/停用旧的 PiP v2.x 扩展，避免重复监听 `generation_ended`。
2. 安装 `sillytavern-native-pip-extension-v3.0.0.zip`。
3. 重启 SillyTavern。

扩展里应该看到：

- `PiP视频开启`
- `开启系统通知`
- `测试系统横幅`

在普通 Safari 中会显示“原生壳：未连接”；在下面这个 iOS App 中会显示“原生壳：已连接”。

## 第二步：用 Xcode 安装 iPhone App

1. macOS 安装 Xcode。
2. 双击 `SillyTavernNativePiP.xcodeproj`。
3. 左侧点项目 → TARGETS → `SillyTavernNativePiP` → Signing & Capabilities。
4. Team 选择你自己的 Apple ID / Developer Team。
5. Bundle Identifier 如发生冲突，改成你自己的唯一值。
6. 用数据线或无线调试连接 iPhone。
7. 顶部设备选择你的 iPhone，点击 Run。

项目已经写入你的网站地址：

`http://aaa.xixisillytavern.top:8001/`

如果以后改网站，只需修改：

`SillyTavernNativePiP/AppConfig.swift`

## 第三步：测试

1. 从刚安装的 `SillyTavernNativePiP` App 打开 SillyTavern。
2. 打开“扩展程序 → PiP 原生桥接支架”。
3. 状态应显示 `原生壳：已连接`。
4. 点 `开启系统通知`，在 iPhone 权限弹窗选择允许。
5. 点 `测试系统横幅`：应该出现 iOS 系统横幅并有通知声音。
6. 点 `PiP视频开启`：应该出现系统 PiP 小窗。
7. 切到其他 App，让 SillyTavern 生成回复；回复结束时应收到横幅。

## PiP 视频怎么换

扩展会把自身 `pip-loop.mp4` 的真实 URL 发给原生 App，因此以后只需要覆盖 SillyTavern 扩展目录里的：

`pip-loop.mp4`

不需要重新编译 iOS App。

推荐：H.264 MP4、无音轨、360p~720p、几秒到几十秒循环。

原生壳同时打包了一个很小的备用 `Resources/pip-loop.mp4`，用于无法获得远程视频 URL 时的兜底。

## 5 分钟

当前扩展向原生层传 `maxDurationSeconds: 300`，PiP 最长 5 分钟后自动退出。要改时长，在扩展 `index.js` 里修改这一项即可。

## HTTP 说明

你当前地址是 HTTP。项目的 `Info.plist` 已仅针对 `aaa.xixisillytavern.top` 添加 ATS 例外：

`NSExceptionAllowsInsecureHTTPLoads = true`

因此 Xcode 安装到手机后可以直接打开 `:8001` 的 HTTP 服务。

不过 HTTP 不加密账号、Cookie 和聊天流量；如果这个服务经过公网，建议后续给域名加 HTTPS。上架 App Store 时，HTTP ATS 例外也可能需要额外说明。

## 通知的边界

这版是“原生本地通知”：只要 SillyTavern 页面实际收到 `generation_ended`，就会让原生层发横幅。PiP 激活时 App 具备后台媒体运行条件，适合你目前“切出去看视频，等回复”的使用方式。

如果以后要求 **App 被强制退出/网页完全不运行时，服务器仍然主动把回复完成推到 iPhone**，则需要第二阶段：APNs Device Token + Apple Developer Push Key + SillyTavern 后端 Server Plugin。那是远程 Push，不是这版的本地通知。


## v1.1.2 修复：GitHub Web/Windows 上传后的脚本权限

如果旧版日志出现：

```text
./scripts/build-unsigned-ipa.sh: Permission denied
```

这是 GitHub/Windows 上传时没有保留 Unix 可执行权限造成的。v1.1.2 的工作流改为 `bash ./scripts/build-unsigned-ipa.sh`，因此不再依赖脚本的 executable bit。


## v1.1.3 构建修复

GitHub Actions 的 IPA 构建已改成完全内联 workflow，不再依赖 `scripts/build-unsigned-ipa.sh`。即使某些 Xcode Runner 在已经打印 `BUILD SUCCEEDED` 后仍返回 65，workflow 会单独检查 `.app`、Info.plist 和主可执行文件；产物完整就继续打包 IPA。日志中应出现 `WORKFLOW_VERSION=v1.1.3-INLINE`。


## v1.2.0 后台回复完成通知修复

这一版与前端扩展 v3.1.0 配合：回复生成期间，扩展在 WKWebView 内播放无声保活音轨；原生壳把 AVAudioSession 固定为 `playback + mixWithOthers`。目的不是发声，而是避免 iOS 在切到后台后冻结 WKWebView 的生成完成事件，同时尽量不打断其它 App 的视频声音。生成完成/停止后会停止网页保活音轨。

请同时升级 SillyTavern 前端扩展到 v3.1.0。
