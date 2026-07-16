# MyBill Backend (FastAPI)

Async FastAPI service for the Grocery Bill Intelligence App. See [`../MyBill.md`](../MyBill.md)
for the full architecture and [`../DESIGN.md`](../DESIGN.md) for build status.

## Requirements

- Python **3.12+**
- [`uv`](https://docs.astral.sh/uv/) for dependency management

## Setup

```bash
cd backend
uv sync --dev            # create .venv and install deps + dev tools
cp .env.example .env     # then edit as needed
```

## Run

```bash
uv run uvicorn app.main:app --reload
```

- Health check: <http://localhost:8000/v1/health>
- Interactive docs (non-production only): <http://localhost:8000/docs>

## Quality gates

```bash
uv run ruff check .      # lint
uv run ruff format .     # format
uv run mypy app          # static types (strict)
uv run pytest            # tests
```

## Layout

```
backend/
├── app/
│   ├── main.py              # create_app() factory + ASGI entrypoint
│   ├── core/
│   │   ├── config.py        # Settings (pydantic-settings)
│   │   ├── logging.py       # structured logging + request-id context
│   │   ├── middleware.py    # request-id + access logging
│   │   ├── responses.py     # standard response envelope (MyBill.md §5)
│   │   └── exceptions.py    # AppError hierarchy + handlers
│   └── api/
│       └── v1/
│           ├── router.py    # aggregates all v1 routers
│           └── routes/
│               └── health.py
└── tests/
    ├── conftest.py
    └── test_health.py
```

## Conventions

- **Config:** never read `os.environ` directly — inject `get_settings()`.
- **Responses:** return `app.core.responses.success(...)`; raise `AppError` subclasses
  for expected failures. Both render the uniform envelope.
- **Logging:** no PII (receipt totals, item names) in log messages — MyBill.md §11.
