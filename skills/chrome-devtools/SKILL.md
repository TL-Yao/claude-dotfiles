---
name: chrome-devtools
description: Chrome DevTools MCP deep reference. Use for performance testing (Core Web Vitals, LCP, CLS, INP), network request inspection, HAR export, Lighthouse audits, or when working with your real Chrome session (OAuth, authenticated pages). Requires chrome://inspect/#remote-debugging to be enabled in Chrome.
---

# Chrome DevTools MCP

Connects to your **real running Chrome** via `chrome://inspect/#remote-debugging`.
Inherits your actual session, cookies, and logins.

**Prerequisite:** Open Chrome → `chrome://inspect/#remote-debugging` → toggle ON.

## Core Workflow

```
1. navigate_page(url)
2. take_snapshot()          → accessibility tree with uid="element-123" refs
3. click(uid) / fill(uid)   → interact using UIDs
4. Inspect tools as needed  → network, console, performance
```

UIDs are session-scoped. Re-run `take_snapshot()` after any navigation or DOM change.

## All 29 Tools

### Navigation
- `navigate_page(url, waitUntil?, initScript?, handleBeforeUnload?)` — Navigate to URL
- `navigate_page_history(direction)` — Back (`-1`) or Forward (`1`)
- `new_page(url?, isolatedContext?)` — New tab (isolatedContext for named cookie contexts)
- `list_pages()` — List all open tabs with IDs
- `select_page(id)` — Switch to tab
- `close_page(id?)` — Close tab (current if no id)
- `wait_for(selector?, text?, time?)` — Wait for element, text, or timeout

### Input Automation
- `click(uid, button?, clickCount?, modifiers?)` — Click element by UID
- `fill(uid, text)` — Fill input field
- `fill_form(uid)` — Fill entire form with field descriptions
- `hover(uid)` — Hover over element
- `drag(startUid, endUid)` — Drag and drop
- `press_key(key, modifiers?)` — Press key (Enter, Tab, Escape, etc.)
- `upload_file(uid, paths[])` — Upload files to input
- `handle_dialog(accept, promptText?)` — Handle alert/confirm/prompt dialogs

### Emulation
- `emulate(colorScheme?, cpuThrottling?, geolocation?, network?, userAgent?, viewport?)` — Unified emulation
- `resize_page(width, height)` — Resize viewport

### Performance
- `performance_start_trace(insights[], reload?, autoStop?)` — Start trace
  - Insight names: `LCPBreakdown`, `DocumentLatency`, `NetworkDependencyTree`, `CLS`, `INP`, `ImageDelivery`, `RenderBlocking`, `SlowCSSSelector`, `ThirdParties`, `Viewport`, `FontDisplay`
- `performance_stop_trace()` — Stop trace, returns file path
- `performance_analyze_insight(insightName, trace)` — Analyze specific insight from trace
- `take_memory_snapshot(filePath)` — Heap snapshot (`.heapsnapshot` extension required)

### Network
- `list_network_requests(resourceTypes?, includePreservedRequests?)` — List requests
  - resourceTypes: `document`, `script`, `stylesheet`, `image`, `font`, `xhr`, `fetch`
  - includePreservedRequests: includes last 3 navigations
- `get_network_request(id)` — Full request details (headers, body, timing)

### Debugging
- `take_screenshot(elements?, filename?)` — Screenshot (returns file path)
- `take_snapshot(elements?)` — Accessibility tree with UIDs
- `evaluate_script(script, arg?)` — Run JavaScript (must return JSON-serializable value)
- `list_console_messages(level?, pattern?)` — All console messages (filter by level/regex)
- `get_console_message(id)` — Specific console message details
- `lighthouse_audit(categories[], url?)` — Lighthouse audit

## Key Workflows

### Performance Audit (LCP + CLS)

```
performance_start_trace(insights=["LCPBreakdown", "CLS"], reload=true)
  → (page loads automatically)
performance_stop_trace()
  → trace_path = <returned path>
performance_analyze_insight(insightName="LCPBreakdown", trace=trace_path)
performance_analyze_insight(insightName="CLS", trace=trace_path)
```

**Core Web Vitals thresholds:**
- LCP: ≤2.5s good, ≤4.0s needs improvement, >4.0s poor
- CLS: ≤0.1 good, ≤0.25 needs improvement, >0.25 poor
- INP: ≤200ms good, ≤500ms needs improvement, >500ms poor

### Network Request Inspection

```
navigate_page(url)
list_network_requests(resourceTypes=["fetch", "xhr"])
  → id list
get_network_request(id)
  → headers, body, timing, status
```

### Authenticated Session Automation

```
# Chrome already has your session from chrome://inspect toggle
navigate_page("https://your-internal-tool.example.com/dashboard")
take_snapshot()
  → UIDs for all elements
click(uid="elem-123")
fill(uid="elem-456", text="value")
```

### Accessibility Validation

```
navigate_page(url)
take_snapshot()
  → check roles, aria-labels, headings hierarchy
  → verify interactive elements have accessible names
  → keyboard nav: press_key("Tab") to cycle focus
```

### Multi-Tab Workflow

```
list_pages()            → get current tab IDs
new_page(url)           → open additional tab
select_page(id)         → switch between tabs
close_page(id)          → close when done
```

## evaluate_script Tips

```javascript
// No-arg form
() => { return document.title }
async () => { return await fetch("/api/data").then(r => r.json()) }

// With arg (pass arg as second param to evaluate_script)
(el) => { return el.innerText }

// Must return JSON-serializable values (no DOM nodes, functions, etc.)
```

## Configuration Note

This MCP uses Node 22 binary path (system Node 20.11 is too old):
```json
{
  "command": "/opt/homebrew/Cellar/node@22/22.22.1_1/bin/npx",
  "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect"]
}
```
`--autoConnect` lazily connects to Chrome when first tool is called. Chrome must have `chrome://inspect/#remote-debugging` enabled.
