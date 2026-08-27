# DevOps Challenge — Solutions

Solutions to the [DevOps Challenge](https://s5tech.notion.site/DevOps-Challenge-19d48905ea77801db898d82997c8f4b2). Each problem is answered in `src/problemN/SOLUTION.md`; diagrams are Mermaid and render directly on GitHub.

| Problem | What's inside | Where |
|---|---|---|
| 1 — Building Castle In The Cloud | HA trading system on AWS (500 rps, p99 < 100ms): in-memory matching engine sharded per pair, Kafka event sourcing, CQRS read path, per-service alternatives, 3-stage scaling plan, cost estimate | [src/problem1](src/problem1/SOLUTION.md) |
| 2 — Diagnose Me Doctor | NGINX LB at 99% disk: ordered diagnostic command chain, decision tree, 6 root causes with impact + zero-downtime recovery each, fleet-wide prevention | [src/problem2](src/problem2/SOLUTION.md) |
| 3 — Debugging issues within system | Docker Compose lab debugged **and fixed — all fixes verified on a live environment** (5 gates: 502 fix, fail-fast under DB stall, Redis-outage tolerance, self-healing restart, applied config). Fixed code sits alongside the report | [src/problem3](src/problem3/SOLUTION.md) |
| 4 — Ship It Twice | Production-ready GitHub Actions CI/CD: backend → EC2 via immutable S3 artifact + CodeDeploy blue/green with alarm-based auto-rollback; frontend → S3/CloudFront with instant pointer-based rollback. OIDC only, no static keys | [src/problem4](src/problem4/SOLUTION.md) |
| 5 — Fortify The Castle | Security integrated into the Problem 1 architecture: threat model, changes marked per layer, ship-blockers vs deferred vs accepted risks, missing facts + assumptions | [src/problem5](src/problem5/SOLUTION.md) |

## Running Problem 3

```bash
cd src/problem3
docker compose up -d --build
curl localhost:8080/api/users   # {"ok":true,...}
```

The original (broken) lab is preserved in the upstream repo; this copy contains the fixes described in the report.

## Notes

- Problem 1/5 are design documents by nature; Problem 3 includes working code verified end-to-end; Problem 4 workflows are complete and runnable once real ARNs/bucket names are filled in (no AWS account was used, as the assignment allows).
- Assumptions are declared explicitly at the end of each report.
