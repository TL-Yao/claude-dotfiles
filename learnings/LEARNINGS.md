# Global Learnings
<!-- last-cleanup: 2026-03-08 -->

Cross-project learnings that apply beyond any single project.
Before adding a new entry, grep for similar entries first.

Format: [date] category | status

---

## 2026-03-08 hooks | active

**Summary**: Claude Code prompt hook `{ok: false}` does not grant Claude a new turn — use command hook exit code 2 instead
**Details**: Prompt hooks returning `{ok: false, reason: "..."}` send feedback but don't actually let Claude continue working (known bug #20221, closed as Not Planned). Command hooks with exit code 2 + stderr is the only reliable mechanism for blocking Stop/SubagentStop events and continuing the conversation. Also: command hooks read input from stdin (not $ARGUMENTS), and Stop decision uses exit code 2 (not JSON `{"decision": "block"}`).
**Action**: Always use `type: "command"` with exit code 2 for Stop hooks that need to block. Never use prompt hooks for blocking Stop events.
**Occurrences**: 1
**Projects**: skillPlayground

## 2026-03-09 web-scraping | active

**Summary**: Web scraping 分两层：下载（突破防护）vs 提取（HTML→正文），选工具时要区分
**Details**: trafilatura (5400+ stars) 火爆不是因为反爬能力，而是 HTML 正文提取质量业界领先（双算法 jusText+readability 融合、元数据提取、多格式输出）。它对 Cloudflare 零处理——无 JS 执行、无 TLS 指纹、无 challenge 检测，遇到防护会静默返回垃圾内容。大部分网站无需反爬，所以用户觉得"好用"。真正需要突破防护的场景应组合使用：反爬工具（reader-mcp/Playwright）负责下载 + 提取工具（trafilatura）负责清洗。
**Action**: 选爬虫工具时先问"瓶颈在下载还是提取"——下载受阻选 reader-mcp/Playwright，提取质量差选 trafilatura，两者可组合。
**Occurrences**: 1
**Projects**: skillPlayground

## 2026-03-09 security | active

**Summary**: dotfiles/config 导出脚本必须自动清洗 secrets，不能依赖人工检查
**Details**: export.sh 将 ~/.claude.json 导出为 template 时，直接复制了 Apify API token 到 Git 仓库，触发 GitHub Secret Scanning 拦截 push。修复：用 git-filter-repo --replace-text 重写历史彻底移除 token，export.sh 加 regex 自动清洗已知 secret 模式（apify_api_*, API_KEY, SECRET_KEY, ACCESS_TOKEN, TELEGRAM_*TOKEN）。泄露的 token 必须立即吊销轮换。
**Action**: 任何导出配置到 Git 的脚本，必须内置 secret 清洗步骤，绝不依赖人工审查。新增 MCP/服务集成时检查是否引入了新的 token 模式，及时更新清洗 regex。
**Occurrences**: 1
**Projects**: claude-dotfiles

## 2026-03-09 apify-proxy | active

**Summary**: Cloudflare Turnstile 检测 Playwright CDP `Runtime.Enable`，stealth/proxy 无效；用 Camoufox 或纯 httpx 绕过
**Details**: Cloudflare 不看 UA/指纹/IP，而是检测 Playwright 的 CDP 协议命令（`Runtime.Enable`）。所以 stealth plugin、locale/timezone 伪装、residential proxy 全部无效。解决方案：(1) Camoufox（反检测 Firefox，C++ 层 patch，Apify 有官方 actor `apify/camoufox-scraper`，~$5-10）；(2) 纯 httpx（如果数据在 SSR `__NEXT_DATA__` 里，根本不需要浏览器）。EdgeProp 实测：本地 httpx HTTP 200，SSR 包含几乎所有数据。
**Action**: 遇到 Cloudflare 站点先检查数据是否在 SSR（httpx 直接拿），否则用 Camoufox（非 Playwright）。不要浪费时间调 Playwright stealth。
**Occurrences**: 2
**Projects**: rentSift

## 2026-03-09 git | active

**Summary**: `git filter-repo` 会将工作目录文件 revert 回历史版本，未提交的修改会丢失
**Details**: 在有未提交修改的情况下运行 `git filter-repo --invert-paths`，历史清理成功但工作目录被重置为最后一次 commit 的状态，所有本地修改丢失。必须先 commit 或 stash 修改，再跑 filter-repo。
**Action**: 运行 `git filter-repo` 前，先 commit 或 stash 所有工作目录变更。
**Occurrences**: 1
**Projects**: rentSift

## 2026-03-09 db-schema-migration | active

**Summary**: DB 初始化函数不要用 DROP TABLE — schema 变更用 CREATE IF NOT EXISTS + ALTER TABLE ADD COLUMN
**Details**: `get_db()` 里为了配合新 schema，写了 `DROP TABLE IF EXISTS` + `CREATE TABLE`。第一次运行没问题，但爬虫中途崩溃后重启，又触发了 DROP，导致已爬的 829 条数据全部丢失。正确做法是 `CREATE TABLE IF NOT EXISTS` + 用 `PRAGMA table_info` 检测缺失列再 `ALTER TABLE ADD COLUMN`。
**Action**: DB 初始化永远不要 DROP TABLE。Schema 迁移用 additive migration（只加列）。破坏性 schema 变更单独写迁移脚本，手动执行。
**Occurrences**: 1
**Projects**: rentSift

## 2026-03-11 team-coordination | active

**Summary**: Team lead must NOT take over teammates' work — idle notifications are normal, not signs of being stuck
**Details**: Designer-architect sent idle notifications while working on a revision. Team lead mistakenly interpreted repeated idles as "stuck" and rewrote the entire design spec, overwriting the teammate's file. User rightfully called this out as a major mistake. Idle notifications are normal turn intervals between message processing. Team lead's role is to coordinate and delegate, never to implement teammates' tasks.
**Action**: (1) Never take over a teammate's assigned work. (2) Idle notifications ≠ stuck. Be patient. (3) If genuinely concerned, send ONE ping and wait. (4) If teammate truly unresponsive after reasonable time, discuss with user before taking action.
**Occurrences**: 1
**Projects**: rentSift

## 2026-03-11 mapbox-gl | active

**Summary**: Mapbox GL `<Layer filter={undefined}>` crashes — always pass a valid filter array or omit the prop
**Details**: react-map-gl's `<Layer>` passes the `filter` prop directly to `map.addLayer()`. Mapbox GL expects `filter` to be an array (expression) or absent — `undefined` triggers `"array expected, undefined found"` error and silently prevents the layer from rendering. Building polygons disappeared because `typeFilter` returned `undefined` when both types were selected.
**Action**: Never pass `filter={undefined}`. Use a "match all" expression like `['has', 'type']` or conditionally spread `{...(filter ? { filter } : {})}`.
**Occurrences**: 1
**Projects**: rentSift

## 2026-03-12 remote-server-management | active

**Summary**: Claude Code 远程服务器管理三条路线：原生 SSH、classfang MCP（推荐）、bvisible MCP（重度）
**Details**: (1) Claude Code Desktop 原生 SSH：SSH 进远端直接跑 Claude Code，全能力但需远端装 Node+CC，适合远程开发；(2) `classfang/ssh-mcp-server`（65 stars，MCP 官方收录，NPX 直接跑，凭证隔离+命令黑白名单，命令执行+文件传输）—— 推荐作为全局通用方案 `claude mcp add -s user ssh-mcp-server -- npx -y ssh-mcp-server`；(3) `bvisible/mcp-ssh-manager`（18 stars，37 工具/6 组，服务器分组批量执行/DB 备份/SSH 隧道/sudo，context 优化减 92% token）—— 适合重度 DevOps。简单一次性任务 `ssh` one-shot 也够用。
**Action**: 跨项目通用方案装 `classfang/ssh-mcp-server`（`-s user` 全局）。重度运维加装 `bvisible/mcp-ssh-manager`。一次性任务直接 `ssh` one-shot。
**Occurrences**: 1
**Projects**: freelandGate

## 2026-03-09 background-tasks | active

**Summary**: Claude Code 后台任务在 cooling pause / sleep 期间会被回收，长时间爬虫用 `nohup` 启动
**Details**: 用 Bash tool 的 `run_in_background` 启动的爬虫进程，在 `asyncio.sleep(120-300)` cooling pause 期间被系统 kill（exit 143 = SIGTERM）。进程没有错误日志，数据无丢失但中断了。改用 `nohup python3 script.py > /dev/null 2>&1 &` 启动后不再被回收。
**Action**: 超过 30 分钟的后台任务，用 `nohup` 而非 Claude Code 的 `run_in_background`。确保脚本有 progress 文件支持断点续跑。
**Occurrences**: 1
**Projects**: rentSift

