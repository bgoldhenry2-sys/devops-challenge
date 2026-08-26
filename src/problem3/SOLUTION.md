# Problem 3: Debugging issues within system

> Docker Compose lab (nginx → Node.js api → postgres + redis). Reported symptom: "API unreliable and sometimes inaccessible". All fixes have been verified on a live running environment (evidence in §4); the fixed code lives in this same directory.

## 1. Issues found

### Bug A — Port mismatch: nginx points to 3001, API listens on 3000 (loss of access through the LB)

`nginx/conf.d/default.conf` proxies to `http://api:3001` while the app calls `listen(3000)` → **every `/api/` request through nginx returns 502**.

### Bug B — Requests hang forever when Postgres is slow/unresponsive (source of "sometimes inaccessible")

`pg.Pool` defaults: `connectionTimeoutMillis=0` (wait forever), no query timeout. When Postgres does not respond (network stall, overload): requests hang indefinitely, each hung request holds 1 pool slot → all 10 slots exhausted → **the API stops responding for all users**.

### Bug C — Pool leak on query errors

The original pattern `pool.connect() → query() → release()`: if `query()` throws, `release()` never runs → **1 connection is permanently lost on every error**. After N scattered errors the pool is exhausted → the API degrades gradually until it stops serving — matching the "unreliable" symptom: works intermittently, recovers after a restart, then recurs.

### Bug D — Redis being down breaks/slows the API even though it is only an auxiliary dependency

`redis.set("last_call")` sits on the main request path + ioredis defaults to 20 retries per command → when Redis is down, every request **waits several seconds then returns 500**, even though Redis only records telemetry that does not affect the result. In addition, the `redis.on('error')` handler is missing → errors are logged repeatedly at high frequency.

### Bug E — No self-healing, no startup ordering

No `restart` policy (when the api crashes, the service stays down until restarted manually); no `healthcheck`; `depends_on` has no condition → the api starts before postgres is ready → errors at boot.

### Bug F — Postgres has no volume (data lost on recreate)

A stateful service without persistence — recreating the container loses all data.

### Bug G — Dead config & other configuration issues

- `postgres/init.sql` (`max_connections=20`) is **not mounted** into the container → the config has no effect, and easily misleads a code reader into believing this limit is being enforced. Fix: mount it into `docker-entrypoint-initdb.d/` and keep the app pool (10) < 20.
- `nginx/nginx.conf` is empty and not mounted — the file is unused, excluded from the analysis scope.
- `.env` is empty; the Dockerfile runs as root, no `NODE_ENV=production`.

## 2. Diagnostic approach

1. **Read statically first, run later**: tracing the port chain (compose → nginx conf → `app.listen`) uncovered Bug A; tracing the connection lifecycle (connect/release) uncovered Bug C.
2. **Deliberate reproduction on a live running environment** — one experiment per hypothesis:

| Experiment | Result on the ORIGINAL version | Conclusion |
|---|---|---|
| `curl :8080/api/users` through nginx | 502, nginx log `connect() failed ... upstream http://...:3001` | Bug A confirmed |
| Hitting `api:3000` directly inside the container | 200 OK | The app works fine — the failure is only at the routing layer |
| `docker pause postgres` then hit | Hangs forever (request aborted at 6s, still no response) | Bug B confirmed |
| `docker stop redis` then hit | Long wait, 500 `MaxRetriesPerRequestError ... limit (20)` | Bug D confirmed |

## 3. Fixes applied (files in this directory)

| File | Change |
|---|---|
| `nginx/conf.d/default.conf` | `proxy_pass http://api:3000` (port fixed); added `proxy_connect_timeout 2s`, `proxy_read_timeout 10s` — the LB fails fast instead of hanging the client |
| `api/src/index.js` | Pool: `max=10`, `connectionTimeoutMillis=2000`, `statement_timeout=5000` (server-side), `query_timeout=5000` (client-side — also covers the case where the server does not respond); switched to `pool.query()` (auto acquire + release even on error → eliminates the leak); Redis: `maxRetriesPerRequest=1`, best-effort in its own try/catch (Redis being down does not fail the request), added `on('error')`; added `/ready` (readiness separated from `/status` liveness); graceful shutdown on SIGTERM |
| `docker-compose.yml` | `healthcheck` for all 4 services; `depends_on: condition: service_healthy` (correct startup order); `restart: unless-stopped` (self-healing); `pgdata` volume (data survives recreate); mounted `init.sql` (config actually applied, pool 10 < max_connections 20); mounted nginx conf `:ro`; removed `version` (obsolete) |
| `api/Dockerfile` | `NODE_ENV=production`, `npm install --omit=dev`, `USER node` |

## 4. Verification evidence (live run, Docker 28.3.2)

```
GATE 1  curl /api/users through nginx    → HTTP 200, 0.036s
GATE 2  docker pause postgres → hit      → HTTP 500 after 2.0s (fail fast, no more hang)
GATE 3  docker stop redis → hit          → HTTP 200, 0.005s (Redis down has no impact)
GATE 4  kill PID 1 inside api container  → auto restart, healthy after 7s, hit → HTTP 200
GATE 5  SHOW max_connections             → 20 (init.sql actually applied)
```

Experiment note: `docker kill` on a container is treated by Docker as a manual stop, so the restart policy does not trigger — crash-recovery testing must kill the process inside the container.

## 5. Monitoring / alerts to add

- **Blackbox probe** `GET /api/users` through the LB (the exact path users take) — alert when error rate >1% or p99 > threshold; probe `/ready` to separate the case of "api running but a dependency not ready".
- **Application metrics**: pool in-use/idle/waiting (catches Bug C-style leaks before exhaustion), request duration histogram, error count per route.
- **Infrastructure**: container restart count (a restart loop = a bug being masked by the policy), Postgres connections used / max_connections (alert at 80%), Redis up.
- **Logs**: nginx 5xx rate; structured app errors — the appearance of `MaxRetriesPerRequestError` immediately pinpoints Redis as the cause, no guesswork needed.

## 6. Production prevention

1. **Fail-fast by default**: every DB/cache client must declare timeouts + bounded retries right from the service template — never rely on library defaults.
2. **Classify hard vs. soft dependencies**: auxiliaries (telemetry, cache writes) must be best-effort, off the critical path.
3. **Healthcheck + restart policy as a mandatory standard** for every service in compose/K8s manifests; liveness separated from readiness.
4. **Static checks in CI**: lint compose (ports match conf, stateful services must have volumes, forbid unmounted config files), smoke test `docker compose up` + curl in the pipeline — Bug A-class errors must be blocked before reaching production.
5. **Failure load testing (light chaos)**: pause/stop each dependency in staging as in §2 — the method used to uncover Bugs B/D.
