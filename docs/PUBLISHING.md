# 上传到 GitHub

建议仓库名称：`opencode-sessions`。建议描述：

> A lightweight Windows GUI for managing and resuming local OpenCode conversations.

建议 topics：`opencode`、`windows`、`wpf`、`csharp`、`session-manager`、`desktop-app`。

## 使用 Git 上传（推荐）

在 GitHub 创建空仓库，不要额外生成 README、许可证或 `.gitignore`，本项目已经包含这些文件。

在此文件的上两级目录，即包含 `README.md`、`app/`、`.github/` 的仓库根目录打开 PowerShell，运行：

```powershell
git init -b main
git add .
git status --short
git commit -m "Initial open-source release of OpenCode Sessions"
```

如 Git 尚未设置提交身份，可仅对当前仓库设置：

```powershell
git config user.name "Xiaohei Wu"
git config user.email "xiaohei.wu@whu.edu.cn"
```

然后重新执行提交命令。在下列地址中把 `YOUR_GITHUB_USERNAME` 替换成你实际的 GitHub 用户名：

```powershell
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/opencode-sessions.git
git push -u origin main
```

## 使用网页上传

解压源码包，把**目录里面的文件和子目录**上传到仓库根目录，使 README 直接位于首页。请包含 `.github`、`.gitignore`、`.gitattributes` 和 `.editorconfig`；这些文件名以点开头，容易漏选。

源码 ZIP 用于解压后上传，不要仅把 ZIP 本身作为仓库中的唯一文件。不要上传 `dist/`、EXE、用户设置或真实会话。

## 创建第一个 Release

1. 查看 Actions 的 Windows build 是否通过；云端首次运行仍需检查。
2. 本地运行 `scripts/Package.ps1`，或下载 Actions 的构建产物。
3. 在 GitHub 创建 `v6.0.0` 标签对应的 Release。
4. 上传 Windows ZIP 和它的 `.sha256` 文件，发布说明参考 `CHANGELOG.md`。

此目录没有预设远端、GitHub 用户名、访问令牌或自动发布凭据。上述步骤由仓库拥有者执行。
