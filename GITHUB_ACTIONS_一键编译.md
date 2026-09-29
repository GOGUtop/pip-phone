# GitHub Actions 一键编译 v1.3.0

将本目录全部上传到 GitHub 仓库根目录，然后进入：

`Actions → Build iPhone IPA → Run workflow`

正常日志必须包含：

`WORKFLOW_VERSION=v1.3.0-INLINE`

构建完成后在运行页面底部下载 Artifact：

`SillyTavernNativePiP-IPA-<编号>`

主要文件：`SillyTavernNativePiP-unsigned.ipa`

这是未签名 IPA，需要使用 SideStore、Sideloadly 或 AltStore 等工具签名后安装。
