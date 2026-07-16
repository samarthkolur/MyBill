# MyBill — Grocery Bill Intelligence App

Photograph a grocery receipt, get it turned into structured data automatically, and see
spending analytics, price trends, and bill comparisons over time.

- **Architecture & product spec:** [`MyBill.md`](./MyBill.md) — the full system design (data flow, DB schema, API design, OCR pipeline, phased roadmap).
- **Build status & task tracker:** [`DESIGN.md`](./DESIGN.md) — single source of truth for what's done, what's next, and every design decision made along the way. Read this before picking up any task.

## Stack

- **Mobile:** Flutter (Riverpod, GoRouter, Freezed)
- **Backend:** FastAPI (async SQLAlchemy, Celery + Redis for the OCR pipeline)
- **Data:** Supabase (PostgreSQL, Auth, Storage)

## Repository layout

```
MyBill/
├── backend/    # FastAPI service (API, OCR pipeline, workers)
├── mobile/     # Flutter app
├── infra/      # Docker Compose, Supabase migrations/config
├── docs/       # Supplementary docs
├── MyBill.md   # Architecture & product spec
└── DESIGN.md   # Living build log / task tracker
```

## Status

Early foundation phase — see [`DESIGN.md`](./DESIGN.md) for the current milestone and next task.
