---
name: watchdog-integration
description: Use when integrating WatchDog analytics into a project — adding request tracking middleware, pageview tracking, SQL schema setup, or deploying the watchdog-api dashboard. Triggers include "add analytics", "add monitoring", "track requests", "integrate watchdog", "pageview tracking", "analytics middleware", "usage analytics".
---

> **Sync rule:** This skill reflects the watchdog project at `/Users/tongleyao/claudeProjects/watchDog/`.
> If the watchdog project code changes, this skill MUST be updated to match.

# WatchDog Integration Guide

Self-hosted web analytics. SDK writes to PostgreSQL, API reads from it, Dashboard visualizes.

```
Your App + SDK/Middleware (writes) --> PostgreSQL <-- watchdog-api (reads) <-- Dashboard (displays)
```

## 1. Database Setup (All Languages)

Run the migration on PostgreSQL 15+:

```bash
psql -U <user> -d <dbname> -f /path/to/watchdog/migrations/001_analytics.sql
```

Creates three tables:
- `analytics_requests` — backend request tracking (indexes on created_at, tenant, user_id, path, status_code, session_id)
- `analytics_pageviews` — frontend page view tracking (indexes on created_at, tenant, path, session_id)
- `analytics_meta` — key-value store (tracks dropped_events)

**Schema columns** (for manual middleware in Python/Node):

`analytics_requests`: id (BIGSERIAL PK), tenant (VARCHAR 100), user_id (VARCHAR 100), username (VARCHAR 200), user_role (VARCHAR 50), session_id (VARCHAR 100), method (VARCHAR 10 NOT NULL), path (VARCHAR 500 NOT NULL), raw_path (VARCHAR 500), query_string (VARCHAR 1000), status_code (SMALLINT NOT NULL), duration_ms (INTEGER NOT NULL), request_size (INTEGER), response_size (INTEGER), error_message (VARCHAR 1000), ip (VARCHAR 45 NOT NULL), user_agent (VARCHAR 500), created_at (TIMESTAMPTZ NOT NULL DEFAULT NOW())

`analytics_pageviews`: id (BIGSERIAL PK), tenant (VARCHAR 100), user_id (VARCHAR 100), username (VARCHAR 200), session_id (VARCHAR 100), path (VARCHAR 500 NOT NULL), referrer (VARCHAR 500), duration_on_prev (INTEGER), viewport_width (SMALLINT), viewport_height (SMALLINT), ip (VARCHAR 45 NOT NULL), user_agent (VARCHAR 500), created_at (TIMESTAMPTZ NOT NULL DEFAULT NOW())

## Phase A: Code Integration

Integrate tracking into your application code (Sections 2-5).

## 2. Go SDK Integration (Gin)

```bash
go get github.com/TL-Yao/watchdog/sdk/go@latest
```

```go
import (
    watchdog "github.com/TL-Yao/watchdog/sdk/go"
    "gorm.io/gorm"
)

// REQUIRED: Create analytics tables (without this, all tracking data is silently lost)
if err := watchdog.AutoMigrate(db); err != nil {
    log.Fatalf("Failed to migrate analytics tables: %v", err)
}

// Create collector (buffered async writer)
collector := watchdog.NewCollector(db, watchdog.Config{
    ExcludeIPs:    strings.Split(os.Getenv("WATCHDOG_EXCLUDE_IPS"), ","),
    BufferSize:    2048,           // channel buffer size
    FlushInterval: 5 * time.Second,
    FlushCount:    100,
})
defer collector.Close() // CRITICAL: flushes remaining events on shutdown

// Add middleware to Gin router
r.Use(watchdog.GinMiddleware(collector, watchdog.GinOptions{
    TenantExtractor:   func(c *gin.Context) string { return c.GetHeader("X-Tenant-ID") },
    UserIDExtractor:   func(c *gin.Context) string { return c.GetString("user_id") },
    UsernameExtractor: func(c *gin.Context) string { return c.GetString("username") },
    RoleExtractor:     func(c *gin.Context) string { return c.GetString("user_role") },
    SessionExtractor:  func(c *gin.Context) string { return "" }, // optional
    SkipPaths:         []string{"/health", "/metrics"},
}))

// Add pageview endpoint for frontend tracker
r.POST("/track/pageview", collector.HandlePageview(watchdog.PageviewOptions{
    TenantExtractor:   func(c *gin.Context) string { return c.GetHeader("X-Tenant-ID") },
    UserIDExtractor:   func(c *gin.Context) string { return c.GetString("user_id") },
    UsernameExtractor: func(c *gin.Context) string { return c.GetString("username") },
    SessionExtractor:  func(c *gin.Context) string { return "" },
}))
```

### Key Behaviors

- **Non-blocking writes**: Channel full -> events dropped (counted in `analytics_meta.dropped_events`)
- **IP exclusion**: IP-only via `ExcludeIPs`, no header-based mechanism. Uses `c.ClientIP()`
- **Error capture**: Status >= 400 -> first 1000 bytes of response body captured as `error_message`
- **Pageview IP**: Always server-side `c.ClientIP()`, never from request body
- **Extractors**: Return `""` for missing values (stored as NULL in DB)

### Env Vars

```bash
WATCHDOG_EXCLUDE_IPS=10.0.0.1,10.0.0.2  # comma-separated admin IPs
```

## 3. Python Integration (Manual Middleware)

Run SQL migration first (Section 1), then add middleware.

### Django Middleware

```python
import time
import psycopg2
from django.conf import settings

class WatchdogMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        self.conn_params = settings.WATCHDOG_DB_DSN
        self.exclude_ips = set(getattr(settings, 'WATCHDOG_EXCLUDE_IPS', []))

    def __call__(self, request):
        start = time.monotonic()
        response = self.get_response(request)
        duration_ms = int((time.monotonic() - start) * 1000)

        ip = self._get_client_ip(request)
        if ip in self.exclude_ips:
            return response

        error_msg = None
        if response.status_code >= 400:
            error_msg = getattr(response, 'content', b'')[:1000].decode('utf-8', errors='replace')

        try:
            conn = psycopg2.connect(self.conn_params)
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO analytics_requests
                    (tenant, user_id, username, user_role, method, path, raw_path,
                     query_string, status_code, duration_ms, error_message, ip, user_agent)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    getattr(request, 'tenant', None),
                    str(request.user.id) if request.user.is_authenticated else None,
                    getattr(request.user, 'username', None),
                    getattr(request.user, 'role', None),
                    request.method,
                    request.resolver_match.route if request.resolver_match else request.path,
                    request.path,
                    request.META.get('QUERY_STRING', '')[:1000] or None,
                    response.status_code,
                    duration_ms,
                    error_msg,
                    ip,
                    request.META.get('HTTP_USER_AGENT', '')[:500] or None,
                ))
            conn.commit()
            conn.close()
        except Exception:
            pass  # analytics should never break the app

        return response

    def _get_client_ip(self, request):
        xff = request.META.get('HTTP_X_FORWARDED_FOR')
        return xff.split(',')[0].strip() if xff else request.META.get('REMOTE_ADDR', '')
```

### FastAPI Middleware

```python
import time
from starlette.middleware.base import BaseHTTPMiddleware
import psycopg2

class WatchdogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        start = time.monotonic()
        response = await call_next(request)
        duration_ms = int((time.monotonic() - start) * 1000)

        ip = request.headers.get("x-forwarded-for", request.client.host).split(",")[0].strip()
        if ip in EXCLUDE_IPS:
            return response

        try:
            conn = psycopg2.connect(DB_DSN)
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO analytics_requests
                    (method, path, raw_path, query_string, status_code, duration_ms, ip, user_agent)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    request.method,
                    request.url.path,
                    request.url.path,
                    str(request.query_params) or None,
                    response.status_code,
                    duration_ms,
                    ip,
                    request.headers.get("user-agent", "")[:500] or None,
                ))
            conn.commit()
            conn.close()
        except Exception:
            pass
        return response
```

**Note**: For production Python apps, use a connection pool (e.g., `psycopg2.pool`) and consider async writes via a background queue.

## 4. Node/Express Integration (Manual Middleware)

Run SQL migration first (Section 1), then add middleware.

```javascript
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.WATCHDOG_DB_DSN });
const excludeIPs = new Set((process.env.WATCHDOG_EXCLUDE_IPS || '').split(',').filter(Boolean));

function watchdogMiddleware(req, res, next) {
  const start = Date.now();

  res.on('finish', () => {
    const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
    if (excludeIPs.has(ip)) return;

    const durationMs = Date.now() - start;
    let errorMsg = null;
    if (res.statusCode >= 400 && res._body) {
      errorMsg = String(res._body).slice(0, 1000);
    }

    pool.query(
      `INSERT INTO analytics_requests
       (method, path, raw_path, query_string, status_code, duration_ms, error_message, ip, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        req.method,
        req.route?.path || req.path,
        req.originalUrl.split('?')[0],
        req.originalUrl.includes('?') ? req.originalUrl.split('?')[1].slice(0, 1000) : null,
        res.statusCode,
        durationMs,
        errorMsg,
        ip,
        (req.headers['user-agent'] || '').slice(0, 500) || null,
      ]
    ).catch(() => {}); // never break the app for analytics
  });

  next();
}

// Usage
app.use(watchdogMiddleware);
```

**Pageview endpoint** (Express):

```javascript
app.post('/track/pageview', express.json(), (req, res) => {
  const { path, referrer, duration_on_prev, viewport_width, viewport_height, session_id } = req.body;
  if (!path) return res.sendStatus(400);

  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
  if (excludeIPs.has(ip)) return res.sendStatus(204);

  pool.query(
    `INSERT INTO analytics_pageviews
     (path, referrer, duration_on_prev, viewport_width, viewport_height, session_id, ip, user_agent)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [path, referrer || null, duration_on_prev || null, viewport_width || null, viewport_height || null,
     session_id || null, ip, (req.headers['user-agent'] || '').slice(0, 500) || null]
  ).catch(() => {});

  res.sendStatus(204);
});
```

## 5. Frontend Pageview Tracker

### Core Tracker (Framework-agnostic)

```typescript
const PAGEVIEW_ENDPOINT = '/track/pageview';

async function trackPageview(path: string, referrer?: string) {
  try {
    await fetch(PAGEVIEW_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        path,
        referrer: referrer || document.referrer,
        viewport_width: window.innerWidth,
        viewport_height: window.innerHeight,
        session_id: getOrCreateSessionId(),
      }),
    });
  } catch {} // never break the app
}

// Session ID with 30-min inactivity expiry
function getOrCreateSessionId(): string {
  const KEY = 'wd_session';
  const EXPIRY = 30 * 60 * 1000;
  const stored = sessionStorage.getItem(KEY);
  if (stored) {
    const { id, ts } = JSON.parse(stored);
    if (Date.now() - ts < EXPIRY) {
      sessionStorage.setItem(KEY, JSON.stringify({ id, ts: Date.now() }));
      return id;
    }
  }
  const id = crypto.randomUUID();
  sessionStorage.setItem(KEY, JSON.stringify({ id, ts: Date.now() }));
  return id;
}
```

### React Integration

```tsx
import { useEffect, useRef } from 'react';
import { useLocation } from 'react-router-dom';

function usePageTracking() {
  const location = useLocation();
  const prevPath = useRef(location.pathname);
  const enterTime = useRef(Date.now());

  useEffect(() => {
    const durationOnPrev = Date.now() - enterTime.current;
    trackPageview(location.pathname);
    // Optionally send duration_on_prev for the previous page
    prevPath.current = location.pathname;
    enterTime.current = Date.now();
  }, [location.pathname]);
}

// Call in your App component:
// usePageTracking();
```

### Vue Integration

```typescript
// In router setup
router.afterEach((to, from) => {
  trackPageview(to.path, from.fullPath);
});
```

## Phase B: Server Deployment

After code integration is complete, build and deploy (Sections 6-7).

## 6. watchdog-api Deployment

### Build

```bash
cd /path/to/watchdog/api
go build -o watchdog-api .
```

### Configuration

| Flag | Env Var | Default | Description |
|------|---------|---------|-------------|
| `--db-dsn` | `WATCHDOG_DB_DSN` | (required) | PostgreSQL connection string |
| `--listen` | `WATCHDOG_LISTEN` | `127.0.0.1:9090` | Listen address |
| `--retention-days` | `WATCHDOG_RETENTION_DAYS` | `90` | Auto-delete data older than N days |

Priority: flag > env > default. Retention cleanup runs on startup + every 24h.

### Systemd Service

```ini
[Unit]
Description=WatchDog Analytics API
After=postgresql.service

[Service]
Type=simple
User=watchdog
Environment=WATCHDOG_DB_DSN=postgres://user:pass@localhost:5432/analytics
Environment=WATCHDOG_LISTEN=127.0.0.1:9090
Environment=WATCHDOG_RETENTION_DAYS=90
ExecStart=/usr/local/bin/watchdog-api
Restart=always

[Install]
WantedBy=multi-user.target
```

### Docker

```dockerfile
FROM golang:1.25-alpine AS build
WORKDIR /app
COPY api/ .
RUN go build -o watchdog-api .

FROM alpine:3
COPY --from=build /app/watchdog-api /usr/local/bin/
EXPOSE 9090
ENTRYPOINT ["watchdog-api"]
```

```bash
docker run -d --name watchdog-api \
  -e WATCHDOG_DB_DSN="postgres://user:pass@host:5432/db" \
  -p 9090:9090 watchdog-api
```

### API Endpoints

All under `/api/v1/`. Common params: `from`, `to` (YYYY-MM-DD), `tenant` (optional).

| Endpoint | Description |
|----------|-------------|
| `GET /overview` | DAU, MAU, requests, pageviews, avg response, error rate, dropped events |
| `GET /trends/dau` | Daily active users over time |
| `GET /trends/errors` | 4xx/5xx counts and error rate per day |
| `GET /rankings/pages?limit=20` | Top pages by views |
| `GET /rankings/apis?limit=20` | Top APIs by calls (includes P95) |
| `GET /rankings/errors?limit=20` | Top errors by count |
| `GET /activity/tenants` | Per-tenant DAU, requests, pageviews, error rate |
| `GET /activity/users?limit=20` | Per-user activity |
| `GET /distribution/hourly` | Requests + pageviews by hour (0-23) |
| `GET /meta/tenants` | Distinct tenant list for filter dropdowns |

## 7. Dashboard Connection

### Add Project

Edit `dashboard/dashboard.config.json`:

```json
{
  "projects": [
    {
      "name": "MyApp",
      "apiUrl": "http://localhost:9090",
      "tunnel": "ssh -L 9090:127.0.0.1:9090 deploy@myserver.com -N"
    }
  ]
}
```

### SSH Tunnel (Remote Servers)

```bash
# Single project
ssh -L 9090:127.0.0.1:9090 deploy@myserver.com -N

# Multiple projects: add entries to dashboard.config.json with different ports
# and create a tunnel-all.sh script:
#!/bin/bash
ssh -L 9090:127.0.0.1:9090 deploy@server1 -N &
ssh -L 9091:127.0.0.1:9090 deploy@server2 -N &
wait
```

### Run Dashboard

```bash
cd dashboard
npm install
npm run dev  # http://localhost:5173
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Forgetting `defer collector.Close()` (Go) | Events in buffer are lost on shutdown |
| Extracting IP from request body | Always extract server-side (handles X-Forwarded-For) |
| Adding header-based admin exclusion | IP-only by design — use ExcludeIPs / WATCHDOG_EXCLUDE_IPS |
| Running AutoMigrate without SQL migration | AutoMigrate creates tables but NOT indexes |
| String-interpolating user input into SQL | Always use parameterized queries ($1, %s, ?) |
| Letting analytics errors crash the app | Wrap in try/catch, never propagate analytics failures |
| Missing `watchdog.AutoMigrate(db)` call (Go) | Analytics tables won't exist — all tracking data is silently lost |
