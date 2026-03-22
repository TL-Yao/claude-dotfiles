---
name: browser-router
description: Entry point for ALL browser tasks. Invoke this before using any browser tool. Routes between agent-browser (headless automation, default), chrome-devtools (performance/network/real Chrome session), and claude-in-chrome (screenshots/GIF). Triggers on any request involving websites, web pages, browser automation, form filling, clicking, web testing, visual verification, or screenshot tasks.
---

# Browser Tool Router

Three tools are available. Pick based on the task, then execute with the right tool.

## Decision Tree

```
Need a GIF recording?                           → claude-in-chrome
Need visual screenshot of YOUR real browser?    → claude-in-chrome
                                                   (mcp__claude-in-chrome__computer)

Need performance data / Lighthouse audit?       → chrome-devtools
Need network request inspection / HAR?          → chrome-devtools
Need to work on a page you're already logged in → chrome-devtools (uses your real Chrome session)
  to (OAuth, internal dashboards, banking)?       Prerequisite: chrome://inspect/#remote-debugging ON

Everything else (default):                      → agent-browser
  - Headless web scraping
  - Form automation
  - Multi-step workflows
  - Data extraction
  - Web testing
  - Simple screenshots
```

---

## agent-browser — Default Tool

**Daemon-based Bash CLI. Runs headless, low token cost, fast.**

### Core workflow

```bash
# 1. Navigate
agent-browser open <url>

# 2. Snapshot (get element refs)
agent-browser snapshot -i
# Output: - button "Submit" [ref=e1]  - textbox "Email" [ref=e2]

# 3. Interact using refs
agent-browser fill @e2 "user@example.com"
agent-browser click @e1

# 4. Re-snapshot after navigation/DOM changes
agent-browser snapshot -i
```

### Key commands

```bash
agent-browser open <url>                   # Navigate
agent-browser snapshot -i                  # Interactive elements with @refs
agent-browser snapshot -i -C              # Include divs with onclick
agent-browser click @e1                   # Click
agent-browser fill @e2 "text"             # Clear + type
agent-browser press Enter                 # Press key
agent-browser wait --load networkidle     # Wait for page load
agent-browser wait --text "Welcome"       # Wait for text to appear
agent-browser screenshot                  # Screenshot to temp dir
agent-browser screenshot --annotate       # Screenshot with numbered labels
agent-browser get url                     # Current URL
agent-browser get title                   # Page title
agent-browser console                     # View console messages
agent-browser errors                      # View JS errors
agent-browser close                       # Close browser
```

### Authentication (for protected sites)

```bash
# Option 1: Borrow auth from user's running Chrome (one-off)
agent-browser --auto-connect state save ./auth.json
agent-browser --state ./auth.json open https://app.example.com/dashboard

# Option 2: Persistent profile (best for recurring tasks)
agent-browser --profile ~/.myapp open https://app.example.com/login
# Login once, then always authenticated:
agent-browser --profile ~/.myapp open https://app.example.com/dashboard

# Option 3: Session name (auto save/restore cookies)
agent-browser --session-name myapp open https://app.example.com
```

### Command chaining

```bash
# Chain when you don't need intermediate output
agent-browser open https://example.com && agent-browser wait --load networkidle && agent-browser snapshot -i

# Chain interactions
agent-browser fill @e1 "user@example.com" && agent-browser fill @e2 "pass" && agent-browser click @e3
```

---

## chrome-devtools — Performance, DevTools, Real Chrome Session

**MCP server. Connects to your running Chrome (with your real session).**

**Prerequisite:** Chrome must have `chrome://inspect/#remote-debugging` toggle ON.

### Core workflow

```
1. navigate_page (url)
2. take_snapshot  → returns accessibility tree with uid="elem-123" refs
3. Interact: click(uid), fill(uid, text), fill_form(uid)
4. Inspect: list_network_requests, get_console_message, take_screenshot
```

### When to use

- **Performance audit**: LCP, CLS, INP measurement via `performance_start_trace` + `performance_analyze_insight`
- **Network debugging**: `list_network_requests` → `get_network_request` for request details/HAR
- **You're already logged in**: OAuth, Google Workspace, internal tools — chrome-devtools inherits your real cookies
- **Lighthouse audit**: `evaluate_script` with Lighthouse, or use performance tools
- **Multi-tab workflows**: `list_pages` → `select_page` → `new_page` → `close_page`

### Key tools

```
navigate_page(url)                         Navigate
take_snapshot()                            Accessibility tree (returns UIDs)
click(uid)                                 Click by UID from snapshot
fill(uid, text)                            Fill input by UID
fill_form(uid)                             Fill multiple fields at once
handle_dialog(accept, promptText?)         Handle alerts/confirms/prompts
take_screenshot()                          Screenshot
evaluate_script(script)                    Run JavaScript
get_console_message(id)                    Get specific console message
list_console_messages()                    All console messages
list_network_requests(resourceTypes?)      Network requests
get_network_request(id)                    Request details
performance_start_trace(insights, reload)  Start performance trace
performance_stop_trace()                   Stop + save trace
performance_analyze_insight(name, trace)   Analyze: LCPBreakdown, DocumentLatency, etc.
resize_page(width, height)                 Resize viewport
new_page(url?, isolatedContext?)           New tab
list_pages()                               List open tabs
select_page(id)                            Switch tab
```

### Performance audit pattern

```
performance_start_trace(insights=["LCP", "CLS"], reload=true)
→ wait for page load
performance_stop_trace()
→ performance_analyze_insight(insightName="LCPBreakdown", trace=<path>)
→ performance_analyze_insight(insightName="DocumentLatency", trace=<path>)
```

**Note:** UIDs from `take_snapshot` are specific to this session. Re-run `take_snapshot` after navigation.

---

## claude-in-chrome — Screenshots, GIF, Visual Verification

**MCP extension. Shares your real Chrome session. Best for visual tasks.**

### When to use

- Recording multi-step interactions as GIF
- Taking screenshots of your real browser state
- Visual debugging (see what the page actually looks like)
- Tasks where seeing the page visually matters

### Key tools

```
mcp__claude-in-chrome__tabs_context_mcp()          Get current tabs (always call first)
mcp__claude-in-chrome__tabs_create_mcp(url?)        New tab
mcp__claude-in-chrome__navigate(tabId, url)         Navigate
mcp__claude-in-chrome__computer(tabId, action)      Click/type/screenshot
mcp__claude-in-chrome__find(tabId, query)           Find element
mcp__claude-in-chrome__read_page(tabId)             Read page structure
mcp__claude-in-chrome__get_page_text(tabId)         Get page text
mcp__claude-in-chrome__read_console_messages(tabId) Console logs
mcp__claude-in-chrome__gif_creator(tabId, path)     Record GIF
mcp__claude-in-chrome__javascript_tool(tabId, code) Run JavaScript
```

### GIF recording pattern

```
1. mcp__claude-in-chrome__tabs_context_mcp()   ← always start here
2. mcp__claude-in-chrome__tabs_create_mcp()
3. mcp__claude-in-chrome__gif_creator(tabId, "output.gif")  ← start recording
4. mcp__claude-in-chrome__navigate(tabId, url)
5. mcp__claude-in-chrome__computer(tabId, {action: "screenshot"})  ← capture frames
6. [... interactions ...]
7. mcp__claude-in-chrome__computer(tabId, {action: "screenshot"})  ← final frame
8. mcp__claude-in-chrome__gif_creator(tabId, "output.gif")  ← stop recording
```

---

## Quick Comparison

| Scenario | Tool |
|---|---|
| Web scraping / data extraction | agent-browser |
| Form automation | agent-browser |
| Multi-step headless workflows | agent-browser |
| Site is behind OAuth / your login | chrome-devtools |
| Performance audit (LCP, CLS) | chrome-devtools |
| Network request debugging | chrome-devtools |
| "What does this page look like?" | agent-browser screenshot |
| Screenshot of YOUR real Chrome tab | claude-in-chrome |
| Recording a demo GIF | claude-in-chrome |
| Visual UI regression testing | claude-in-chrome |
