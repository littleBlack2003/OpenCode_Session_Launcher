# 构建、测试与发布

## 工具链

Windows PowerShell 5.1、.NET Framework 4.8 与 Windows 自带 `csc.exe`。不需要 NuGet、npm、Python 或额外下载的 .NET SDK。

## 常用命令

从仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1
```

构建生成 `app/OpenCodeSessions.exe` 和安装校验清单。测试编译一个控制台测试程序并生成 `tests/gui-preview.png`。这些都是被 Git 忽略的产物。

`-Live` 仅适用于本机已安装 OpenCode 且存在会话时：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Live
```

默认离线测试不需要 OpenCode，验证路径、参数、退出码、搜索、持久化、消息解析和 WPF 离屏布局。安装测试将注册表操作替换为模拟 PATH 文件，并把快捷方式定向到临时目录。它们不等同于真实桌面点击或真实终端的端到端测试。

## 图标

`app/App.xaml` 中的 `AppLogo` 是几何图形源。重新生成图标：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -RefreshLogo
```

SVG、PNG、ICO 都提交到 Git；开发者无需为了普通代码改动重新生成图标。更新公开截图时，请使用合成数据，把测试生成图复制到 `docs/images/gui-preview.png`。

## 发布

`scripts/Package.ps1` 会构建并执行离线测试，生成：

```text
dist/OpenCodeSessions-v6.0.0-windows.zip
dist/OpenCodeSessions-v6.0.0-windows.zip.sha256
```

版本号从 EXE 的程序集版本读取。发布 ZIP 含程序、安装器、旧 CLI、用户说明、MIT LICENSE、更新记录和逐文件校验清单，不包含测试程序、用户数据或源码开发工具。

发布新版本前，更新 `Manager.cs` 的程序集版本、`app.manifest` 的版本、GUI 的版本标签、安装器显示文字与 CHANGELOG。CI 会构建、测试并上传产物，但不会自动对外发布 Release。

## GitHub Actions

`.github/workflows/windows.yml` 在推送、PR 或手动触发时运行，使用 Windows runner。Actions 依赖固定到提交 SHA，并由 Dependabot 提议更新；工作流仅请求读取仓库内容的权限。

CI 的入口与本地相同：`scripts/Package.ps1`。首次上传后请查看 Actions 页面确认实际云端运行状态。
