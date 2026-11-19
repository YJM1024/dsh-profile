# DSH profile：Windows + Mac 双向同步

这个仓库就是 DSH 桌面端 `desktop` profile 的本体，两台机器各自 clone 一份，
`sync-tools/` 里的脚本负责双向同步。**不是单向下发**：任何一台机器的改动
（装插件、改主题、改 `cordis.patch.yml`）都会被提交并推到远端，另一台 pull 下来。

## 当前基线

- bundle 共 **24 个**：本机 23 个 + Mac 侧独有的 `dsh-usage-stats`。
  （`@deepseek-ai/dsh-base` 和 `@deepseek-ai/dsh-web-app` 两台都有，所以 23 + 3 − 2 = 24。）
- 插件配置以本机（Windows）现值为准；Mac 侧原来的 4 条配置是它的子集。
  `ui-settings-account`、`ui-chat` 两条两台取值不同，属于「机器习惯」，
  按下一节的办法留在各自本机，不进仓库。

## 同步什么

| 内容 | 进仓库 | 说明 |
|---|---|---|
| `package.json` | ✅ | bundle 清单 + 第三方依赖 |
| `cordis.patch.yml` | ✅ | 插件开关、插件配置、外观/字号 |
| `pnpm-lock.yaml`、`pnpm-workspace.yaml`、`cordis.yml` | ✅ | 版本锁定与 profile 骨架 |
| `vendor/` | ✅ | 两个本地 tgz 插件 + `dsh-preset-council` 预设的源码 |
| `node_modules/` | ❌ | 平台相关，各机器自己 install |
| `.plugin-manager/`、`.dsh-market/` | ❌ | 本机日志与市场缓存 |

永远不进仓库：`~/.dsh/.credentials.yaml`、会话、工作区、`dsh-runtimes/`、
以及每台机器自己的 `$DSH_HOME/cordis.patch.yml`（见下一节）。

## 配置分层：共享的进仓库，每机的留在 `$DSH_HOME`

DSH 启动 profile 时按顺序叠 patch 层（`@deepseek-ai/dsh-app-boot` 的
`readProfilePatches`）：

1. 每个 bundle 自带的 `cordis.patch.yml`
2. profile 自己的 `cordis.patch.yml` ← 在仓库里，两台共享
3. `$DSH_HOME/cordis.patch.yml` ← 只在这台机器上，**压过**第 2 层
4. 命令行 `--patch` 覆盖

所以「两台各保留各的」不需要新机制：第 3 层本来就是干这个的，而且它在 profile
目录之外，git 看不见，永远不会冲突。

目前放第 3 层的两条：

| 行 id | Windows | macOS |
|---|---|---|
| `ui-settings-account` | office / compact / compact / 开发者工具关 | development / standard / detailed / 开发者工具开 |
| `ui-chat` | compact / compact | standard / detailed |

模板见 `sync-tools/machine/cordis.patch.windows.yml` 与 `…macos.yml`。两个安装
脚本会在 `$DSH_HOME/cordis.patch.yml` **不存在**时拷一份过去，已存在就原样保留。

想再加只属于本机的配置，直接写进 `$DSH_HOME/cordis.patch.yml`。注意 patch 是
**整行替换**：覆盖某一行时，要把那一行的所有字段重新写全（漏字段会退回默认值）。

**代价（已知且刻意接受）**：被 home 层覆盖的行，在设置界面里改不动。DSH 的配置
编辑器只写 profile 的 `cordis.patch.yml`，写完后发现还有更高优先级层压着，会直接
报 `Configuration for "<id>" is overridden by a home patch or command-line overlay`。
所以这两项要改成**改这个文件**，不是改设置界面。想恢复「两边同一个值、界面可改」，
把 `$DSH_HOME/cordis.patch.yml` 里对应行删掉，再把值写回 profile 的
`cordis.patch.yml` 即可。

## 为什么有三个依赖放在 `vendor/`

原来的 `package.json` 里这三条是 Windows 绝对路径，Mac 上 `pnpm install` 必然失败：

```diff
- "@local/dsh-preset-council": "link:E:/dsh_home/workspaces/presets/dsh-preset-council"
+ "@local/dsh-preset-council": "file:./vendor/dsh-preset-council"
- "dsh-achievements": "file:E:/dsh_home/plugins/vendor/dsh-achievements-0.1.7.tgz"
+ "dsh-achievements": "file:./vendor/dsh-achievements-0.1.7.tgz"
- "dsh-token-usage-dashboard": "file:E:/dsh_home/plugins/vendor/dsh-token-usage-dashboard-1.0.1.tgz"
+ "dsh-token-usage-dashboard": "file:./vendor/dsh-token-usage-dashboard-1.0.1.tgz"
```

`file:` 用相对路径后两台机器都能解析。代价：升级这三个插件要重新拷进 `vendor/` 并提交，
不能只改本机文件。

## 一次性设置

### Windows（本机）

这台机器的网络情况特殊，按下面的顺序做：

1. **Git**：`github.com:443` 在本机是**超时**的，winget 装 Git 会在下载阶段失败。
   现成可用的是便携版，解压在 `E:\dsh_home\tools\PortableGit`（不占 C 盘）。
   便携版没进系统 PATH，所以定时任务靠 `DSH_GIT_BASH` 找它：
   ```powershell
   [Environment]::SetEnvironmentVariable('DSH_GIT_BASH','E:\dsh_home\tools\PortableGit\bin\bash.exe','User')
   ```
2. **传输走 SSH over 443**（HTTPS 在本机推不上去）。`~/.ssh/config` 里要有：
   ```
   Host github.com
       HostName ssh.github.com
       Port 443
       User git
       AddressFamily inet
       ConnectTimeout 15
       IdentitiesOnly yes
       IdentityFile ~/.ssh/id_ed25519
   ```
   `AddressFamily inet` 不是可选项：本机 DNS 对 `ssh.github.com` 的 **AAAA 查询会
   返回 server failure**，ssh 双栈解析偶尔直接失败（`Could not resolve hostname`），
   锁成 IPv4 就稳定了。
   公钥加到 GitHub 后，`git -C <profile> ls-remote` 应该能列出 `refs/heads/main`。
   仓库转 private 之后这条路照样可用，不需要 token。
3. **依赖**：npmjs 官方源在本机约 170 KB/s，npmmirror 约 1.3 MB/s，安装时指定后者：
   ```powershell
   $node = 'E:\dsh_home\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
   $pnpm = 'E:\dsh_home\dsh-runtimes\dsh-primary-runtime\dependencies\pnpm\bin\pnpm.cjs'
   & $node $pnpm install --registry=https://registry.npmmirror.com
   ```
   > `dsh-usage-stats` 用的是 codeload tarball 直链而不是 `github:` 简写：
   > `github:` 会先 `HEAD https://github.com/...`，本机这条路会挂住几分钟。
4. **注册定时任务**（当前用户权限即可）：
   ```powershell
   powershell -ExecutionPolicy Bypass -File sync-tools\install-windows.ps1
   ```
   脚本把 `DSH_SYNC_PROFILE` 直接写进任务命令行，因为计划任务不继承会话环境变量。
   它还会在 `$DSH_HOME\cordis.patch.yml` 不存在时用 Windows 模板播种本机的
   配置层（已存在则不动）。

### Mac

Mac 上 profile 目录已经是仓库，正常 `git pull` 即可，然后装一次依赖：

```sh
cd ~/.dsh/profiles/desktop
git pull
pnpm install
```

定时任务（`launchd`，默认 900 秒一次）：

```sh
sh sync-tools/install-macos.sh          # 15 分钟
sh sync-tools/install-macos.sh 300      # 5 分钟
```

它注册 `~/Library/LaunchAgents/com.yjm1024.dsh-sync.plist`，并把 `dsh-sync`
软链到 `~/.local/bin/dsh-sync`，日志在 `${DSH_HOME:-$HOME/.dsh}/dsh-sync.log`。
它同样会在 `$DSH_HOME/cordis.patch.yml` 不存在时播种 macOS 配置层。

**新机器**（profile 还不存在）才需要 clone：

```sh
cd ~/.dsh/profiles
git clone git@github.com:YJM1024/dsh-profile.git desktop
cd desktop && pnpm install
```

## 日常

```sh
dsh-sync status    # 看分支、远端、待提交改动
dsh-sync push      # 提交并推送
dsh-sync pull      # 拉取远端
dsh-sync sync      # 提交 + 拉取 + 推送（定时任务跑的就是这个）
```

`dsh-sync.sh` 的 profile 路径取值顺序：`DSH_SYNC_PROFILE` → `$DSH_HOME/profiles/desktop`
→ `~/.dsh/profiles/desktop`，Windows 上会用 `cygpath` 把反斜杠路径转成 POSIX 路径。
日志默认 `$DSH_HOME/dsh-sync.log`。

配置层开着 HMR，`cordis.patch.yml` 拉下来会直接热生效。但 `package.json` 变了
（新增插件）必须 `pnpm install` 再重启 DSH，否则插件页会报加载失败。

## 冲突

脚本遇到 rebase 冲突会 **abort 并保持本地原样**，不会替你选。手工处理：

```sh
cd <profile>
git status
# 解完
git add -A && git rebase --continue
```

两个平台各自 `pnpm install` 会让 `pnpm-lock.yaml` 分叉，这是最可能撞的地方。
想直接放弃远端、保留本地：`git rebase --abort` 然后 `dsh-sync push`。

## 注意

- 仓库**必须私有**：以后给插件配 API key 会写进 `cordis.patch.yml`。
- 定时任务只做 git 操作，**从不**自动 `pnpm install`（会联网、会触发构建审批）。
  所以 pull 下来发现多了插件，要手动补一次 install 再重启 DSH。
- 两台机器同时改 `cordis.patch.yml` 才会冲突；行数很少，正常碰不到。
- **Windows 的 profile 在 Dropbox 里**（`D:\Dropbox\dsh-data\profiles\desktop`），
  也就是 `.git` 和 `node_modules` 都在被 Dropbox 同步。Dropbox 不会理解 git 的
  内部结构，如果它给 `.git/` 里的文件生成「冲突副本」，仓库可能损坏。建议在
  Dropbox 设置里排除 `profiles\desktop\.git`、`node_modules` 和 `.dsh-market`，
  只让 Dropbox 保留数据文件，git 自己走 GitHub 同步。
