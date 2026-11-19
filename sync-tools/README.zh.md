# 同步工具

说明文档只有一份，在仓库根目录：[../README.md](../README.md)。

这个目录里是脚本本身：

| 文件 | 用途 |
|---|---|
| `dsh-sync.sh` | 同步入口，`status` / `push` / `pull` / `sync` 四个子命令 |
| `install-macos.sh` | 注册 macOS `launchd` 定时任务，并把 `dsh-sync` 放进 `~/.local/bin` |
| `install-windows.ps1` | 注册 Windows 计划任务，定时跑 `dsh-sync.sh sync` |
