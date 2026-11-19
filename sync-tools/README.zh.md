# DSH profile 同步工具

这个仓库就是 DSH 桌面端的 `desktop` profile 本体（`~/.dsh/profiles/desktop`），
再加上 `sync-tools/` 里的同步脚本。两台机器各自 clone 一份，就能共用插件清单、
插件配置和主题设置。

## 同步什么

| 内容 | 进仓库 | 说明 |
|---|---|---|
| `package.json` | ✅ | 插件清单（`dsh.profile.bundles`）和第三方依赖 |
| `cordis.patch.yml` | ✅ | 插件开关、插件配置、外观/字号等设置 |
| `pnpm-lock.yaml`、`pnpm-workspace.yaml`、`cordis.yml` | ✅ | 版本锁定和 profile 骨架 |
| `node_modules/` | ❌ | 插件代码，按平台各自安装 |
| `.plugin-manager/` | ❌ | 本地日志 |

不在这个目录、也永远不进仓库的：`~/.dsh/.credentials.yaml`（凭据）、会话、工作区、
`~/.dsh/dsh-runtimes/`（运行时二进制）。

## 一次性设置

### 1. 在 GitHub 建一个空仓库

**私有**，名字建议 `dsh-profile`，不要勾选 README、.gitignore 或 license
（这里已经有内容了，勾了会冲突）。

### 2. Mac（已经有 profile 的这台）

```sh
cd ~/.dsh/profiles/desktop
git remote add origin git@github.com:YJM1024/dsh-profile.git
git push -u origin main
```

Mac 走 SSH（`~/.ssh/id_ed25519` 已经生成好，公钥已加到 GitHub），没有令牌过期问题。

装定时任务：

```sh
sh sync-tools/install-macos.sh          # 默认 15 分钟
sh sync-tools/install-macos.sh 300      # 想改成 5 分钟
```

它会在 `~/Library/LaunchAgents/com.yjm1024.dsh-sync.plist` 注册一个 agent，
并把 `dsh-sync` 命令链接到 `~/.local/bin/dsh-sync`。

### 3. Windows

先装 [Git for Windows](https://git-scm.com/download/win)（自带 Git Bash 和
Git Credential Manager）。然后完全退出 DSH：

```sh
# 如果 %USERPROFILE%\.dsh\profiles\desktop 已经存在，先改名备份
cd %USERPROFILE%\.dsh\profiles
git clone https://github.com/YJM1024/dsh-profile.git desktop
```

如果这台以前装过别的插件，它们不会出现在仓库的清单里；需要的话在 Mac 上把同样的
插件装上，让仓库成为唯一事实来源。

`node_modules` 不跨平台，克隆下来是空的，要用 DSH 自带的 Node + pnpm 装一次
（PowerShell，不需要另外装 Node）：

```powershell
$rt = "$env:USERPROFILE\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies"
$node = @("$rt\node\node.exe", "$rt\node\bin\node.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
Set-Location "$env:USERPROFILE\.dsh\profiles\desktop"
& $node "$rt\pnpm\bin\pnpm.cjs" install
```

第一次 push 要走一次浏览器授权（Git Credential Manager 会弹窗），在 Git Bash 里执行：

```sh
cd ~/.dsh/profiles/desktop && git push
```

再注册定时任务（当前用户权限即可，不需要管理员）：

```powershell
powershell -ExecutionPolicy Bypass -File sync-tools\install-windows.ps1
```

## 日常使用

```sh
dsh-sync status    # 看分支、远端、待提交的改动
dsh-sync push      # 提交本地改动并推送（装完插件、改完主题后跑一下）
dsh-sync pull      # 拉取远端的改动
dsh-sync sync      # 提交 + 拉取 + 推送（定时任务跑的就是这个）
```

配置层默认开着 HMR，所以 `pull` 下来的 `cordis.patch.yml` 会直接热生效，不用重启。
但如果远端新增了插件，还需要在本机装一次依赖，否则插件页会显示加载失败。

## 冲突

脚本遇到 rebase 冲突会**中止并保持本地原样**，日志写在 `~/.dsh/dsh-sync.log`。
手工处理：

```sh
cd ~/.dsh/profiles/desktop
git status
# 解决冲突后
git add -A && git rebase --continue
```

想直接放弃远端、保留本地：`git rebase --abort`，然后 `dsh-sync push`。

## 注意

- 仓库**必须私有**。以后如果给某个插件配了 API key，它会写进 `cordis.patch.yml`。
- 定时任务只做 git 操作，**从不**自动跑 `pnpm install`：装依赖会联网、会触发构建审批，
  不适合无人值守。
- 两台机器同时开着 DSH 又同时改配置，才会产生冲突；配置行数很少，正常不会碰到。
