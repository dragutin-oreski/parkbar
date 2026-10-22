---
tags:
  - backend
about: "make product search answer in under 300 ms"
status: active
priority: 2
target: 2026-10-20
next: "Run the load test against the new index"
updated: 2026-10-19
resume: "claude --resume search-speed-up"
---
**Where I am:** The new index cuts the slow queries from 1.4 s to 250 ms on a copy of the
data. The migration that builds it has not run anywhere shared yet.

| query            | before | after  |
|------------------|--------|--------|
| "shoes"          | 1.4 s  | 0.25 s |
| "red shoes size" | 2.1 s  | 0.31 s |

**Clarify with Bob** — before the load test:
- [ ] Can the index build run during the day, or only overnight?
- [ ] Who watches the database while it builds?

**Then:**

1. Load test on the staging copy.
2. Schedule the build with Bob.
3. Switch reads to the new index.
