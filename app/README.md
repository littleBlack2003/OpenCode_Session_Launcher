# OpenCode Sessions · v6.0 桌面对话管理器

Copyright © 2026 Xiaohei Wu · xiaohei.wu@whu.edu.cn

本项目采用 MIT 许可证，随发行包附带 LICENSE。

软件标志以深绿色对话气泡和代码括号组成。SVG、PNG、ICO 和可编辑图形源在源码仓库的 app/ 目录；发布版已将图标嵌入程序。

一个轻量的 Windows 原生 GUI：搜索和整理本地 OpenCode 会话，预览历史消息，再一键打开 OpenCode 终端继续对话。使用本机已有的 OpenCode，不依赖 fzf、Python、Node 开发环境、浏览器或后台服务。

本项目为独立工具，并非 OpenCode 官方产品。Windows 10 / 11，.NET Framework 4.8。已针对本机 OpenCode 1.18.32 验证会话列表和导出格式；其他版本若 CLI 格式变更可能需要适配。

## 立即使用

解压完整文件夹，双击 **OpenCodeSessions.exe** 即可，无需安装。

- **搜索**：输入标题、项目、路径或会话 ID；空格分隔的词同时匹配。
- **项目筛选**：右上角选择项目；同名项目会显示完整目录以区分。
- **收藏**：常用对话排在最前，在“我的收藏”中集中查看。
- **本地归档**：从主列表收起旧对话；进入“本地归档”点击“移出归档”恢复。原始 OpenCode 会话不会被删除。
- **预览**：右侧显示用户和助手文本、附件名称。工具调用和思考过程不显示；完整数据可导出 JSON。为避免长对话卡顿，只预览最近 60 条文本消息，每条最多 6000 字符，导出不受此限制。
- **继续对话**：点击按钮或在列表上按 Enter / 双击，打开独立 OpenCode 终端。GUI 保持打开。目录不存在时，可选择搬迁后的目录；此映射仅存在管理器中。
- **新建对话**：选一个项目目录，打开该目录中的 OpenCode 终端；创建对话后按 F5 同步列表。
- **导出**：保存 Markdown 文本，或可供 OpenCode 导入的完整 JSON。导出会包含原对话内容，请自行选择保存位置。
- **快捷键**：Ctrl+K 搜索，F5 刷新，搜索框内 Esc 清空关键词。

默认读取最新 1000 个会话，达到上限会显示“加载更多”。也可执行 `ocr.cmd --max-count 3000` 或兼容旧参数 `ocr.cmd -MaxCount 3000`。

GUI 会读取当前进程及系统保存的用户 PATH，并检查 npm、Scoop、常见独立安装路径。找不到 OpenCode 时，点击底部“定位 OpenCode”选择 `opencode.exe` 或 `opencode.cmd`。

## 安装快捷方式和 ocr 命令

双击 **Install.cmd**。无需管理员权限。安装器会校验发布文件，然后：

1. 安装到 `%LOCALAPPDATA%\OpenCodeSessionLauncher`。
2. 在桌面和开始菜单创建 `OpenCode Sessions (ocr)` 快捷方式。
3. 在当前用户 PATH 末尾追加安装目录。

已有 v5 安装可以直接升级：先关闭管理器，再运行新版 Install.cmd。旧核心有变化时会备份为 `ocr-before-install-*.ps1.bak`，旧快捷方式会更新为 GUI。保留原安装清单的 AppId，确保旧版本 PATH 归属信息和卸载逻辑连续。

不添加 PATH：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -NoPath
```

安装后，完全退出终端再重新打开，输入 `ocr`。若 Profile 有旧 `ocr` 别名或函数，请输入 `ocr.cmd`。安装和运行不修改机器级 PATH、PowerShell Profile 或永久执行策略。

## 原终端选择器

保留 `ocr-cli.cmd`，支持 `ocr-cli.cmd -MaxCount 3000`。安装前后均可使用。其核心沿用 v5 的 UTF-8 文件传输逻辑，并修复真实目录被空白清理改写、恢复失败退出码丢失、进程 PATH 过期等问题。GUI 不依赖 fzf。

## 数据位置与卸载

- 会话与消息仍由 OpenCode 保存，通过 `session list` 和 `export` 读取；GUI 不直接改写数据库，不自动调用模型。
- 收藏、归档、手动定位程序和目录映射存放在 `%LOCALAPPDATA%\OpenCodeSessionManager\settings.json`，原子写入并保留 `.bak`。
- 当前版本只管理本机当前用户的 OpenCode 数据，不汇总 WSL、Docker 或远程主机。
- 在实际安装目录运行 **Uninstall.cmd**，确认后移除本安装器添加的 PATH 条目和仍指向本工具的快捷方式。
- 卸载不删除 OpenCode 历史、项目或收藏设置；关闭窗口后可手动删除安装文件夹。

## 从源码构建与测试

在源码仓库根目录运行（发布 ZIP 不包含开发脚本）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1
```

默认测试只使用替身和临时目录。可选 `scripts/Test.ps1 -Live` 只读检查本机 OpenCode 列表和一段会话导出，不发送消息。测试覆盖后端、WPF 离屏渲染和隔离安装，不能替代真实桌面与终端交互验证。更多说明见源码仓库的 docs/DEVELOPMENT.md。

## 参考

- [OpenCode CLI](https://dev.opencode.ai/docs/cli/)
- [PowerShell 进程参数](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)
