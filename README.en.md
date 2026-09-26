<p align="center"><img src="app/logo.png" alt="OpenCode Sessions" width="96" /></p>

# OpenCode Sessions

A lightweight Windows desktop manager for local OpenCode conversations. Find and organize sessions in a native GUI, then continue in the OpenCode terminal.

[中文](README.md) · [MIT license](LICENSE) · [Contributing](CONTRIBUTING.md)

![GUI preview with synthetic data](docs/images/gui-preview.png)

The preview is an offscreen WPF render using synthetic data. This is an independent project, not an official OpenCode product. The current interface is in Simplified Chinese.

## Features

- Search titles, projects, directories and session IDs with multiple keywords.
- Filter by project, pin favorites, and reversibly archive sessions locally.
- Preview conversation text and export Markdown or full OpenCode JSON.
- Resume a session in its original project directory or select a relocated directory.
- Start a new OpenCode terminal session in a chosen folder.
- No browser, background server or fzf required for the GUI.

## Requirements and usage

Windows 10/11, .NET Framework 4.8, and an existing OpenCode CLI installation. The read-only CLI integration was validated with OpenCode 1.18.32. Other versions may require adaptation if their output changes.

Download the Windows ZIP from this repository's Releases, extract it, and run `OpenCodeSessions.exe`. Run `Install.cmd` to add desktop/Start Menu shortcuts and the optional user PATH entry. No administrator access is required. If no release is available, build from source or use this repository's Actions artifact.

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
.\app\OpenCodeSessions.exe
```

`Ctrl+K` searches; `F5` refreshes; `Enter` on the session list resumes a conversation.

## Build and test

```powershell
# Build and run offline tests (does not require OpenCode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1

# Optional read-only checks against local OpenCode sessions
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Live

# Build, test and package a Windows release under dist/
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1
```

No external SDK download is required; scripts use the Windows .NET Framework C# compiler. GitHub Actions runs offline Windows checks and uploads build artifacts. The cloud workflow must be verified after the first push.

## Data and limitations

Sessions are read through `opencode session list` and `opencode export`. The manager does not modify the OpenCode database or send model prompts. Favorites, local archives and relocated directories are stored under `%LOCALAPPDATA%\OpenCodeSessionManager`.

The preview shows the latest 60 text messages, up to 6,000 characters each. JSON export retains the full record. WSL, Docker and remote sessions are not aggregated. Executables are currently unsigned. Automated tests include headless rendering and a fixture-based resume command; they do not replace interactive end-to-end testing with a real terminal.

## License and author

MIT License. Copyright (c) 2026 Xiaohei Wu.  
Contact: **xiaohei.wu@whu.edu.cn**
