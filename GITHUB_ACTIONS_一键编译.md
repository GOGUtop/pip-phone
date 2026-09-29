# GitHub Actions 一键编译 v1.4.0

1. 将本工程内容上传到 GitHub 仓库根目录。
2. 打开 `Actions`。
3. 选择 `Build iPhone IPA`。
4. 点 `Run workflow`。
5. 默认 SillyTavern URL 已是 `http://aaa.xixisillytavern.top:8001/`。
6. 日志确认出现 `WORKFLOW_VERSION=v1.4.0-INLINE`。
7. 完成后在 Artifacts 下载 `SillyTavernNativePiP-IPA-...`。
8. 解压获得 `SillyTavernNativePiP-unsigned.ipa`，再自行签名安装。

v1.4.0 新增原生 Server Monitor，因此服务器上还必须安装 `st-native-monitor v1.0.0`，酒馆前端安装桥接扩展 v3.3.0。
