# GitHub Actions 一键编译 IPA

这个工程已经配置好 GitHub Actions。你不需要 Mac，也不需要本地安装 Xcode；GitHub 的 macOS Runner 会负责把 Swift / Xcode 工程编译成 IPA。

## 第一次上传

1. 在 GitHub 新建一个仓库（Public 或 Private 都可以）。
2. 把本目录里的**所有文件和文件夹**上传到仓库根目录。
3. 特别确认仓库中能看到：
   - `.github/workflows/build-ipa.yml`
   - `SillyTavernNativePiP.xcodeproj`
   - `SillyTavernNativePiP/`
   - `scripts/build-unsigned-ipa.sh`
4. 打开仓库的 **Actions** 页面。
5. 左侧选择 **Build iPhone IPA**。
6. 点右侧 **Run workflow**。
7. `SillyTavern URL` 已默认填写：
   `http://aaa.xixisillytavern.top:8001/`
   地址没变就直接点绿色 **Run workflow**。
8. 等待构建完成（绿色 ✓）。
9. 打开这次运行，在页面底部 **Artifacts** 下载：
   `SillyTavernNativePiP-IPA-数字`
10. 解压 Artifact，里面的主文件就是：
    `SillyTavernNativePiP-unsigned.ipa`

## 这个 IPA 为什么写着 unsigned？

GitHub 可以免费替你编译 iOS 二进制，但不能凭空拥有你的 Apple 开发者签名证书。因此默认生成的是**已编译、未签名 IPA**。

你可以把这个 IPA 直接交给 Sideloadly、SideStore 或 AltStore，由这些工具使用你的 Apple ID / 证书重新签名后安装到 iPhone。

这和“没有编译”不同：Swift 源码已经在 GitHub 的 Xcode 环境里真正编译成 ARM64 iPhone App；剩下只是安装签名。

## 修改网站地址

不用改 Swift 源码。每次点 **Run workflow** 时都可以修改 `SillyTavern URL`。

默认值已经是：

`http://aaa.xixisillytavern.top:8001/`

工作流会在构建前同时修改：
- App 启动 URL
- 允许在 App 内导航的 Host

## HTTP 说明

项目的 `Info.plist` 已经为 `aaa.xixisillytavern.top` 配置 ATS HTTP 例外，所以当前的 `http://...:8001/` 可以由原生 WKWebView 加载。

如果以后换成另外一个 HTTP 域名，除了在 Run workflow 改 URL，还需要给新域名增加 ATS 例外；使用 HTTPS 则不需要 HTTP 例外。

## 构建产物

Artifact 中包含：

- `SillyTavernNativePiP-unsigned.ipa` — 用于 SideStore / AltStore / Sideloadly 重新签名安装。
- `SillyTavernNativePiP-app.zip` — 原始 `.app` 的压缩包，便于其他签名工具使用。
- `SHA256SUMS.txt` — 文件校验值。

## 常见问题

### Actions 页面没有 “Build iPhone IPA”

检查 `.github/workflows/build-ipa.yml` 是否真的位于仓库根目录。GitHub 网页上传文件时不要漏掉 `.github` 文件夹。

### 编译完成但 iPhone 不能直接点 IPA 安装

正常。这个工作流默认不包含你的个人 Apple 证书，所以 IPA 需要先签名。用 Sideloadly / SideStore / AltStore 签名安装即可。

### Actions 报错

打开失败的 workflow run，展开红色步骤，把完整日志截图或复制给 ChatGPT，即可继续针对具体 Xcode 错误修改。


## v1.1.1 修复：GitHub Web/Windows 上传后的脚本权限

如果旧版日志出现：

```text
./scripts/build-unsigned-ipa.sh: Permission denied
```

这是 GitHub/Windows 上传时没有保留 Unix 可执行权限造成的。v1.1.1 的工作流改为 `bash ./scripts/build-unsigned-ipa.sh`，因此不再依赖脚本的 executable bit。
