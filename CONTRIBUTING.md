# 贡献指南

感谢帮助改进 OpenCode Sessions。

## 提交问题

请说明 Windows 和 OpenCode 版本、重现步骤、期望行为与实际行为。截图、日志和示例数据中请去掉真实对话、凭据和私人路径。安全问题请使用 [SECURITY.md](SECURITY.md) 中的私密联系渠道。

## 开发流程

1. Fork 仓库并建立分支。
2. 修改 `app/` 中的源码；界面定义为 `App.xaml`，后端与窗口事件在 `Manager.cs`。
3. 运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1`。
4. UI 改动请检查生成的 `tests/gui-preview.png`，并手动验证真实窗口。
5. 更新相关文档与 `CHANGELOG.md`，在 PR 中说明问题、结果和验证。

## 约定

- 保持 C# 5 / .NET Framework 4.8 兼容，避免引入额外运行时。
- PowerShell 脚本保存为 UTF-8 BOM，兼容 Windows PowerShell 5.1。
- 真实路径不进行显示文本的空白清理；不要拼接不可信 shell 参数。
- 耗时读取应异步执行，并支持取消。
- 自动测试使用临时目录和替身，不写真实注册表、桌面或会话数据库。
- EXE、ZIP、用户配置和真实会话不提交到源码仓库。
- MIT 许可证覆盖本仓库源码与自行创作的图标；提交贡献即表示同意按该许可证分发贡献内容。

构建和发布步骤见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。
