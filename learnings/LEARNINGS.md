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

