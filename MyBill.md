# Grocery Bill Intelligence App — Production Plan

> **Version:** 1.0  
> **Status:** Planning  
> **Stack:** Flutter · FastAPI · Supabase · OCR/Document AI

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture](#2-system-architecture)
3. [Tech Stack & Dependencies](#3-tech-stack--dependencies)
4. [Database Schema](#4-database-schema)
5. [API Design](#5-api-design)
6. [OCR & Parsing Pipeline](#6-ocr--parsing-pipeline)
7. [Flutter App Architecture](#7-flutter-app-architecture)
8. [Analytics Engine](#8-analytics-engine)
9. [Bill Comparison Engine](#9-bill-comparison-engine)
10. [AI & Future Intelligence Layer](#10-ai--future-intelligence-layer)
11. [Security & Auth](#11-security--auth)
12. [Infrastructure & DevOps](#12-infrastructure--devops)
13. [Phased Roadmap](#13-phased-roadmap)
14. [Testing Strategy](#14-testing-strategy)
15. [Performance & Scalability](#15-performance--scalability)
16. [Risk Register](#16-risk-register)

---

## 1. Executive Summary

The Grocery Bill Intelligence App lets users photograph or upload grocery receipts, automatically extracts and structures the data via an OCR pipeline, and surfaces analytics, price trends, spending breakdowns, and intelligent shopping insights over time.

The app is built mobile-first (Flutter), backed by a FastAPI service layer, and persists all data in Supabase (PostgreSQL + Storage). The OCR/Document AI pipeline is designed as a swappable module so the extraction engine can be upgraded without touching the rest of the system.

### Core Value Propositions

| Value                 | Mechanism                                    |
| --------------------- | -------------------------------------------- |
| Effortless capture    | One-tap camera scan or gallery upload        |
| Automatic structuring | OCR → canonical JSON → database              |
| Spending intelligence | Monthly/category/store analytics with charts |
| Price awareness       | Track price changes per item over time       |
| Bill comparison       | Diff any two receipts item by item           |
| AI insights (Phase 6) | Natural language Q&A on purchase history     |

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                       │
│  Camera / Gallery → Riverpod State → GoRouter UI   │
└────────────────────────┬────────────────────────────┘
                         │ HTTPS / REST
┌────────────────────────▼────────────────────────────┐
│                   FastAPI Backend                    │
│  Auth Middleware → Routers → Services → Repos        │
└──────┬─────────────────┬───────────────┬────────────┘
       │                 │               │
┌──────▼──────┐  ┌───────▼──────┐  ┌───▼──────────┐
│  OCR/Doc AI │  │  Supabase DB │  │ Supabase     │
│  Pipeline   │  │  PostgreSQL  │  │ Storage      │
│  (swappable)│  │              │  │ (images/JSON)│
└─────────────┘  └──────────────┘  └──────────────┘
```

### Data Flow

```
User captures image
        ↓
Image uploaded to Supabase Storage (original preserved)
        ↓
FastAPI triggers OCR pipeline
        ↓
Raw OCR JSON saved to Storage
        ↓
Parser normalises → Canonical Receipt JSON
        ↓
Canonical JSON written to PostgreSQL
        ↓
Analytics cache invalidated / updated
        ↓
Flutter app receives structured receipt + renders Digital Bill
```

### Design Principles

- **Immutability of originals.** The raw image and raw OCR output are always kept. Only derived/normalised data is mutable.
- **Modular pipeline.** OCR provider, parser, and AI layer are each behind a clean interface. Swap any one without touching the others.
- **Offline-first UI.** Flutter stores a local cache (Hive/Drift) so recent bills and analytics are available without a network.
- **Analytics caching.** Aggregate queries are pre-computed and cached to keep the dashboard instant.

---

## 3. Tech Stack & Dependencies

### Mobile (Flutter)

| Package                         | Role                              |
| ------------------------------- | --------------------------------- |
| `flutter_riverpod`              | State management                  |
| `go_router`                     | Declarative navigation            |
| `freezed` + `json_serializable` | Immutable models + JSON codegen   |
| `dio`                           | HTTP client with interceptors     |
| `camera`                        | Live camera capture               |
| `image_picker`                  | Gallery upload                    |
| `fl_chart`                      | Analytics charts                  |
| `hive` / `drift`                | Local persistence / offline cache |
| `flutter_secure_storage`        | Token storage                     |
| `image_cropper`                 | Pre-upload crop/rotate            |

### Backend (Python)

| Package              | Role                              |
| -------------------- | --------------------------------- |
| `fastapi`            | API framework                     |
| `uvicorn`            | ASGI server                       |
| `sqlalchemy` (async) | ORM                               |
| `alembic`            | DB migrations                     |
| `pydantic v2`        | Request/response validation       |
| `supabase-py`        | Supabase client (auth + storage)  |
| `python-jose`        | JWT verification                  |
| `celery` + `redis`   | Async OCR job queue               |
| `pillow`             | Image pre-processing              |
| `httpx`              | Async HTTP for OCR provider calls |

### Infrastructure

| Service        | Purpose                                |
| -------------- | -------------------------------------- |
| Supabase       | PostgreSQL + Auth + Storage + Realtime |
| Redis          | Task queue broker + analytics cache    |
| Celery Worker  | Background OCR processing              |
| Docker         | Containerised services                 |
| GitHub Actions | CI/CD                                  |
| Sentry         | Error tracking                         |

---

## 4. Database Schema

All tables include `created_at TIMESTAMPTZ DEFAULT now()` and `updated_at TIMESTAMPTZ` unless noted.

### `users`

```sql
CREATE TABLE users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id),
  email       TEXT NOT NULL UNIQUE,
  full_name   TEXT,
  currency    TEXT NOT NULL DEFAULT 'INR',
  timezone    TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  created_at  TIMESTAMPTZ DEFAULT now()
);
```

### `stores`

```sql
CREATE TABLE stores (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  name_aliases TEXT[],               -- normalised variations
  address      TEXT,
  city         TEXT,
  chain_name   TEXT,                 -- e.g. "DMart", "Reliance Smart"
  UNIQUE (user_id, name)
);
```

### `receipts`

```sql
CREATE TABLE receipts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES users(id) ON DELETE CASCADE,
  store_id         UUID REFERENCES stores(id),
  date             DATE NOT NULL,
  time             TIME,
  total            NUMERIC(10,2) NOT NULL,
  tax              NUMERIC(10,2) DEFAULT 0,
  discount         NUMERIC(10,2) DEFAULT 0,
  payment_method   TEXT,
  image_url        TEXT NOT NULL,     -- Supabase Storage URL (original)
  ocr_json_url     TEXT,              -- raw OCR output
  canonical_json   JSONB,             -- final parsed canonical receipt
  status           TEXT NOT NULL DEFAULT 'pending',
                                      -- pending | processing | done | failed
  ocr_confidence   NUMERIC(4,3),
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ
);
```

### `receipt_items`

```sql
CREATE TABLE receipt_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id      UUID REFERENCES receipts(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  name_normalised TEXT NOT NULL,      -- lowercase, stripped, for matching
  brand           TEXT,
  category_id     UUID REFERENCES categories(id),
  quantity        NUMERIC(8,3) NOT NULL DEFAULT 1,
  unit            TEXT,               -- kg, g, L, ml, pcs
  unit_price      NUMERIC(10,2) NOT NULL,
  total_price     NUMERIC(10,2) NOT NULL,
  ocr_confidence  NUMERIC(4,3),
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

### `categories`

```sql
CREATE TABLE categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,   -- Dairy, Produce, Snacks …
  icon        TEXT,                   -- icon identifier
  color_hex   TEXT
);
```

### `price_history`

```sql
CREATE TABLE price_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  name_normalised TEXT NOT NULL,
  store_id        UUID REFERENCES stores(id),
  unit_price      NUMERIC(10,2) NOT NULL,
  quantity        NUMERIC(8,3),
  unit            TEXT,
  receipt_id      UUID REFERENCES receipts(id),
  date            DATE NOT NULL
);
CREATE INDEX ON price_history (user_id, name_normalised, date);
```

### `analytics_cache`

```sql
CREATE TABLE analytics_cache (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
  cache_key    TEXT NOT NULL,         -- e.g. "monthly:2025-06"
  data         JSONB NOT NULL,
  computed_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, cache_key)
);
```

### Row-Level Security (RLS)

Enable RLS on every table. Each table gets a policy that restricts all operations to `auth.uid() = user_id`. Supabase enforces this automatically; the FastAPI layer uses service-role calls only for system operations (OCR job completion, cache writes).

---

## 5. API Design

Base URL: `https://api.yourdomain.com/v1`

Auth: `Authorization: Bearer <supabase_jwt>` on all endpoints.

### Receipts

| Method   | Path                             | Description                                          |
| -------- | -------------------------------- | ---------------------------------------------------- |
| `POST`   | `/receipts/upload`               | Upload image, create receipt record, enqueue OCR job |
| `GET`    | `/receipts`                      | List receipts (paginated, filterable)                |
| `GET`    | `/receipts/{id}`                 | Get single receipt with items                        |
| `DELETE` | `/receipts/{id}`                 | Soft-delete receipt                                  |
| `GET`    | `/receipts/{id}/items`           | Get line items for a receipt                         |
| `PATCH`  | `/receipts/{id}/items/{item_id}` | Manual correction of an item                         |

### Search

| Method | Path               | Description                                                           |
| ------ | ------------------ | --------------------------------------------------------------------- |
| `GET`  | `/search/receipts` | Full-text search across receipts                                      |
| `GET`  | `/search/items`    | Search items by name, brand, category, store, date range, price range |

### Analytics

| Method | Path                    | Description                                          |
| ------ | ----------------------- | ---------------------------------------------------- |
| `GET`  | `/analytics/summary`    | Dashboard summary (MTD spend, avg basket, top store) |
| `GET`  | `/analytics/monthly`    | Monthly spend for N months                           |
| `GET`  | `/analytics/weekly`     | Weekly breakdown                                     |
| `GET`  | `/analytics/categories` | Spend by category for a period                       |
| `GET`  | `/analytics/stores`     | Spend by store                                       |
| `GET`  | `/analytics/items/top`  | Most frequently purchased items                      |

### Price History

| Method | Path                  | Description                                     |
| ------ | --------------------- | ----------------------------------------------- |
| `GET`  | `/prices/{item_name}` | Price history for a normalised item name        |
| `GET`  | `/prices/trends`      | Items with biggest price changes (period param) |

### Comparison

| Method | Path       | Description                                                |
| ------ | ---------- | ---------------------------------------------------------- |
| `POST` | `/compare` | Body: `{ receipt_a: UUID, receipt_b: UUID }` → diff result |

### OCR Job Status

| Method | Path                    | Description                |
| ------ | ----------------------- | -------------------------- |
| `GET`  | `/receipts/{id}/status` | Poll OCR processing status |

### Standard Response Envelope

```json
{
  "success": true,
  "data": {},
  "meta": {
    "page": 1,
    "total": 42,
    "request_id": "uuid"
  },
  "error": null
}
```

---

## 6. OCR & Parsing Pipeline

The pipeline is the most critical and failure-prone component. It is designed so that each stage is independently retryable and inspectable.

### Stage 1 — Image Pre-processing

Run on the FastAPI worker before calling the OCR provider:

- Resize to max 4000px on the long edge (reduces OCR API cost)
- Convert to grayscale if it aids contrast (detect via histogram)
- Auto-rotate using EXIF data
- Deskew (correct rotation up to ±15°)
- Adaptive binarisation (for crumpled/shadow-heavy receipts)
- Save enhanced image alongside original — never overwrite original

### Stage 2 — OCR

Call the Document AI provider (Google Document AI / AWS Textract / Azure Form Recogniser — pluggable via `OCRProvider` interface):

```python
class OCRProvider(Protocol):
    async def extract(self, image_bytes: bytes) -> OCRResult: ...
```

`OCRResult` contains:

- Raw text
- Bounding boxes per word/line
- Per-word confidence scores
- Provider metadata

Save `OCRResult` as JSON to Supabase Storage immediately.

### Stage 3 — Canonical Parser

Converts `OCRResult` → `CanonicalReceipt`. This is also a swappable module:

```python
class ReceiptParser(Protocol):
    async def parse(self, ocr: OCRResult) -> CanonicalReceipt: ...
```

Parser responsibilities:

- Identify store name (header heuristic, known-store lookup)
- Extract date and time (regex, multiple locale patterns)
- Extract totals, tax, discount lines
- Parse line items: name, brand, quantity, unit, unit price, total price
- Assign preliminary categories (keyword mapping → LLM fallback)
- Score overall OCR confidence
- Flag low-confidence items for manual review

### Canonical Receipt JSON

```json
{
  "store": {
    "name": "DMart",
    "address": "HSR Layout, Bengaluru",
    "chain": "DMart"
  },
  "date": "2025-06-15",
  "time": "18:42",
  "payment_method": "UPI",
  "totals": {
    "subtotal": 1240.0,
    "tax": 62.0,
    "discount": 50.0,
    "total": 1252.0
  },
  "items": [
    {
      "name": "Amul Taaza Full Cream Milk",
      "name_normalised": "amul taaza full cream milk",
      "brand": "Amul",
      "category": "Dairy",
      "quantity": 2,
      "unit": "L",
      "unit_price": 62.0,
      "total_price": 124.0,
      "ocr_confidence": 0.97
    }
  ],
  "ocr_confidence": 0.94,
  "parser_version": "1.2.0"
}
```

### Stage 4 — Normalisation

After parsing, the normalisation layer runs before DB insert:

- Lowercase and strip punctuation for `name_normalised`
- Resolve store aliases (`D-Mart`, `dmart`, `D MART` → `DMart`)
- Map items to canonical product names using a fuzzy alias table
- Assign/confirm categories using the category taxonomy
- Write to `receipt_items` and `price_history`

### Failure Handling

| Failure               | Behaviour                                                             |
| --------------------- | --------------------------------------------------------------------- |
| OCR provider timeout  | Retry ×3 with exponential backoff, then mark `status = failed`        |
| Low confidence (<0.6) | Mark receipt as `needs_review`, surface to user for manual correction |
| Parse exception       | Log full traceback, store raw OCR JSON, mark `status = failed`        |
| Missing total         | Accept partial parse, flag field as `null`, alert user                |

### Celery Task Graph

```
upload_receipt_task
    → preprocess_image_task
        → call_ocr_task
            → parse_receipt_task
                → normalise_and_store_task
                    → invalidate_analytics_cache_task
```

Each task is idempotent: re-running it with the same receipt ID is safe.

---

## 7. Flutter App Architecture

### Layer Structure

```
lib/
├── core/
│   ├── network/          # Dio client, interceptors, error handler
│   ├── storage/          # Hive adapters, secure storage
│   ├── router/           # GoRouter config, route guards
│   └── constants/        # API URLs, theme tokens
├── features/
│   ├── auth/             # login, signup, profile
│   ├── scan/             # camera, gallery, upload progress
│   ├── bills/            # bill list, bill detail, item editor
│   ├── analytics/        # dashboard, charts, filters
│   ├── compare/          # bill comparison picker + diff view
│   ├── search/           # search screen, filters
│   └── settings/         # currency, notifications, export
├── shared/
│   ├── models/           # freezed data classes
│   ├── widgets/          # design system components
│   └── providers/        # cross-feature Riverpod providers
└── main.dart
```

### State Management (Riverpod)

Every feature exposes:

- `*Repository` — pure data access (network + local cache)
- `*NotifierProvider` — state + business logic
- `*State` — freezed union (loading / data / error)

Example for bills:

```dart
@riverpod
class BillsNotifier extends _$BillsNotifier {
  @override
  BillsState build() => const BillsState.loading();

  Future<void> loadBills({BillFilter? filter}) async {
    state = const BillsState.loading();
    final result = await ref.read(billsRepositoryProvider).getReceipts(filter);
    state = result.fold(
      (err) => BillsState.error(err),
      (bills) => BillsState.data(bills),
    );
  }
}
```

### Key Screens

| Screen            | Purpose                                                 |
| ----------------- | ------------------------------------------------------- |
| **Dashboard**     | MTD spend, recent bills, quick-scan FAB                 |
| **Scan**          | Camera viewfinder with capture button + gallery button  |
| **Processing**    | Animated status screen polling `/receipts/{id}/status`  |
| **Bill Detail**   | Full digital receipt with item list, totals, store info |
| **Bill List**     | Paginated, sortable, filterable list of all receipts    |
| **Analytics**     | Tab bar: Monthly · Category · Store · Items             |
| **Compare**       | Pick two bills → animated diff view                     |
| **Search**        | Unified search with facet filters                       |
| **Price History** | Line chart of a product's price over time               |
| **Settings**      | Currency, export (JSON/PDF), account                    |

### Offline Strategy

- Last 30 bills cached in Hive on first load
- Analytics summary cached with 1-hour TTL
- Upload queue persisted locally — if upload fails, retried on next open
- Connectivity monitored via `connectivity_plus`; offline banner shown

---

## 8. Analytics Engine

Analytics are computed server-side, cached in `analytics_cache`, and invalidated whenever a new receipt is successfully processed.

### Metrics

| Metric               | Computation                                                             |
| -------------------- | ----------------------------------------------------------------------- |
| Monthly spend        | `SUM(total)` WHERE `date_trunc('month', date) = target_month`           |
| Weekly spend         | `SUM(total)` WHERE `date_trunc('week', date) = target_week`             |
| Average basket value | `AVG(total)` over trailing 30 days                                      |
| Category breakdown   | `SUM(total_price)` per category, current month                          |
| Top purchased items  | `COUNT(*)` + `SUM(total_price)` per `name_normalised`, trailing 90 days |
| Price trend (item)   | `unit_price` time series from `price_history`                           |
| Store comparison     | `AVG(total)` + `COUNT(*)` per store, trailing 90 days                   |
| Inflation estimate   | Average unit price change for basket of top-20 items, MoM               |
| Savings              | `SUM(discount)` per period                                              |

### Cache Invalidation

On every successful receipt insert, enqueue `invalidate_analytics_cache_task` which deletes or refreshes cache entries whose key matches the affected month/week.

### Chart Types (fl_chart)

| View               | Chart                       |
| ------------------ | --------------------------- |
| Monthly spend      | Bar chart (12 months)       |
| Category breakdown | Donut chart                 |
| Price history      | Line chart with data points |
| Weekly spend       | Bar chart (8 weeks)         |
| Store comparison   | Horizontal bar chart        |

---

## 9. Bill Comparison Engine

### Input

Two receipt IDs. The engine fetches all items for each.

### Algorithm

```
1. Normalise item names on both sides (lowercase, strip punctuation)
2. Build alias map (known aliases from alias table)
3. For each item in Receipt A:
     a. Look for exact match in B by name_normalised
     b. If no exact match, compute cosine similarity on TF-IDF vectors
     c. If similarity > 0.80, treat as same item
4. Classify each item as: COMMON | ADDED (in B only) | REMOVED (in A only)
5. For COMMON items, compute:
     - Quantity delta
     - Unit price delta (absolute + %)
     - Total price delta
6. Roll up category-level totals for both receipts
7. Compute overall total delta
```

### Comparison Response

```json
{
  "receipt_a": {
    "id": "...",
    "date": "2025-05-10",
    "store": "DMart",
    "total": 1200
  },
  "receipt_b": {
    "id": "...",
    "date": "2025-06-15",
    "store": "DMart",
    "total": 1320
  },
  "total_delta": 120,
  "total_delta_pct": 10.0,
  "items": {
    "common": [
      {
        "name": "Amul Taaza Full Cream Milk 1L",
        "qty_a": 2,
        "qty_b": 2,
        "price_a": 62.0,
        "price_b": 68.0,
        "price_delta": 6.0,
        "price_delta_pct": 9.68
      }
    ],
    "added": [{ "name": "Fortune Sunflower Oil 1L", "total_price": 145.0 }],
    "removed": [{ "name": "Lay's Classic Salted 26g", "total_price": 20.0 }]
  },
  "category_delta": {
    "Dairy": { "a": 250, "b": 310, "delta": 60 }
  }
}
```

---

## 10. AI & Future Intelligence Layer

All AI features are gated behind a feature flag and introduced in Phase 6. The layer is additive — no existing features depend on it.

### Architecture

A dedicated `AIService` in FastAPI exposes endpoints that take user context (purchase history window) and return LLM-generated insights. Claude / GPT-4o / Gemini plugged in via a `LLMProvider` interface.

### Planned Capabilities

| Feature                       | Approach                                          |
| ----------------------------- | ------------------------------------------------- |
| Natural language Q&A          | RAG over receipt data + LLM                       |
| Budget prediction             | Time-series model on monthly spend                |
| Restock reminders             | Purchase frequency → predicted next purchase date |
| Duplicate detection           | Embedding similarity on item names                |
| Cheapest store recommendation | Compare price history by item across stores       |
| Shopping list generation      | Recurring items approaching restock date          |
| Meal insights                 | Cluster items into meal patterns                  |

### Example Q&A Queries

- _"What became more expensive in June?"_ → price trend diff, current month vs prior
- _"Which products did I stop buying?"_ → items present >3 times then absent >60 days
- _"Compare June vs July spending."_ → monthly analytics diff
- _"Show all milk purchases."_ → filtered item history

---

## 11. Security & Auth

### Authentication Flow

- Supabase Auth handles registration, login, OAuth (Google)
- JWT issued by Supabase, validated by FastAPI middleware on every request
- Refresh token stored in `flutter_secure_storage` (Keychain / Keystore)
- Session auto-refreshed by Supabase Flutter SDK

### Authorization

- Row-Level Security enforced at DB level (Supabase RLS)
- FastAPI enforces `user_id` scoping in every query — no cross-user data leaks possible at either layer
- Supabase Storage bucket policies: `receipts/{user_id}/` readable only by owner

### Data Security

- All data encrypted at rest (Supabase default: AES-256)
- All traffic over TLS 1.2+
- Image URLs are signed (expiry 1 hour) — not publicly accessible
- API keys for OCR provider stored in environment variables, never in code or client
- No PII logged in application logs; receipt totals and item names are masked in Sentry

### Rate Limiting

- Upload endpoint: 30 requests/hour per user (prevent OCR cost abuse)
- Auth endpoints: standard Supabase rate limiting
- Analytics endpoints: 60 requests/minute per user

---

## 12. Infrastructure & DevOps

### Environments

| Env           | Purpose                                                 |
| ------------- | ------------------------------------------------------- |
| `development` | Local Docker Compose (FastAPI + Redis + local Supabase) |
| `staging`     | Mirrors production; auto-deployed from `main` branch    |
| `production`  | Live environment                                        |

### Docker Compose (development)

```yaml
services:
  api:
    build: ./backend
    env_file: .env
    ports: ["8000:8000"]
    depends_on: [redis]

  worker:
    build: ./backend
    command: celery -A app.worker worker --loglevel=info
    env_file: .env
    depends_on: [redis]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
```

### CI/CD (GitHub Actions)

**On every PR:**

- `ruff` lint + `mypy` type check (backend)
- `flutter analyze` + `flutter test` (frontend)
- Docker build smoke test

**On merge to `main`:**

- Run full test suite
- Build and push Docker image to registry
- Deploy to staging via SSH/ECS/Fly.io action
- Run smoke tests against staging
- Require manual approval for production deploy

### Monitoring

| Tool               | What it monitors                            |
| ------------------ | ------------------------------------------- |
| Sentry             | Backend exceptions, Flutter crash reports   |
| Supabase Dashboard | DB performance, slow queries, storage usage |
| Celery Flower      | Task queue depth, failure rate              |
| Uptime robot       | `/health` endpoint uptime                   |

### Backups

- Supabase automatic daily backups (Point-in-Time Recovery on Pro plan)
- Supabase Storage: versioning enabled on receipt images bucket
- Weekly export of `canonical_json` to cold storage (S3 / GCS)

---

## 13. Phased Roadmap

### Phase 1 — Foundation (Weeks 1–3)

**Goal:** Working app shell with auth and camera.

- [ ] Supabase project setup: Auth, DB (users table), Storage bucket
- [ ] FastAPI skeleton: health check, auth middleware, project structure
- [ ] Flutter: project scaffold, Riverpod setup, GoRouter routes
- [ ] Auth screens: Sign Up, Login, Forgot Password
- [ ] Camera screen: capture + gallery picker
- [ ] Upload endpoint: image to Supabase Storage, return receipt ID with `status = pending`
- [ ] CI pipeline: lint + test on every PR

**Exit criteria:** User can register, log in, photograph a receipt, and see it uploaded.

---

### Phase 2 — OCR Pipeline (Weeks 4–6)

**Goal:** Images become structured data.

- [ ] Choose and integrate OCR provider (Google Document AI recommended)
- [ ] Image pre-processing service (resize, deskew, binarise)
- [ ] Celery + Redis: async job queue
- [ ] `OCRProvider` interface + concrete implementation
- [ ] `ReceiptParser` interface + first implementation
- [ ] Category keyword mapping table (seed 10 categories)
- [ ] Store alias table (seed top 20 Indian grocery chains)
- [ ] Normalisation layer (name normalisation, alias resolution)
- [ ] Write to `receipts`, `receipt_items`, `price_history`
- [ ] Processing status polling endpoint
- [ ] Flutter: animated processing screen

**Exit criteria:** Photographed receipt appears as a structured digital bill within 30 seconds.

---

### Phase 3 — Digital Bill Viewer (Weeks 7–8)

**Goal:** Users can view, browse, and correct their bills.

- [ ] Bill list screen (paginated)
- [ ] Bill detail screen (store, date, items, totals)
- [ ] Inline item correction UI (name, price, category, quantity)
- [ ] PATCH endpoint for item corrections
- [ ] Search endpoint + search screen (store, item, date range)
- [ ] Receipt soft-delete
- [ ] Low-confidence items highlighted for review

**Exit criteria:** Full browse, view, and correct workflow functional.

---

### Phase 4 — Analytics & Charts (Weeks 9–11)

**Goal:** Spending intelligence surfaces to users.

- [ ] Analytics service layer (all 9 metrics)
- [ ] Analytics cache + invalidation
- [ ] Dashboard screen: MTD spend, avg basket, recent bills
- [ ] Monthly spend bar chart (12 months)
- [ ] Category donut chart
- [ ] Store comparison chart
- [ ] Top items list
- [ ] Price history line chart (per item)
- [ ] Date range filter on analytics
- [ ] Export: JSON and PDF (basic layout)

**Exit criteria:** Dashboard loads in <1 second and shows accurate spend breakdowns.

---

### Phase 5 — Bill Comparison (Weeks 12–13)

**Goal:** Diff any two bills.

- [ ] Comparison engine (normalise → alias → cosine similarity)
- [ ] `POST /compare` endpoint
- [ ] Comparison picker screen (select two bills)
- [ ] Diff view: COMMON / ADDED / REMOVED sections
- [ ] Price delta indicators (green/red %, absolute)
- [ ] Category delta summary
- [ ] Total delta header card

**Exit criteria:** User can compare any two bills and see a clear item-level diff.

---

### Phase 6 — AI Insights (Weeks 14–18)

**Goal:** Natural language intelligence layer.

- [ ] `LLMProvider` interface
- [ ] Integrate Claude / GPT-4o via API
- [ ] Context builder: window of receipt data as structured prompt context
- [ ] Q&A endpoint: `POST /ai/ask`
- [ ] Chat UI in Flutter (streaming responses)
- [ ] Restock reminder logic + push notifications
- [ ] Budget prediction model
- [ ] Cheapest store recommendation
- [ ] Feature-flag all AI features (opt-in)

**Exit criteria:** User can ask "What became expensive in June?" and get an accurate, sourced answer.

---

## 14. Testing Strategy

### Backend

| Type                      | Tool                                                   | Coverage target                            |
| ------------------------- | ------------------------------------------------------ | ------------------------------------------ |
| Unit (parser, normaliser) | `pytest`                                               | 90% on core modules                        |
| Integration (endpoints)   | `pytest` + `httpx` + test DB                           | All happy paths + key error paths          |
| OCR pipeline              | Golden-set of 50 real receipt images with known output | Parser accuracy ≥ 85%                      |
| Load                      | `locust`                                               | 100 concurrent uploads without degradation |

### Flutter

| Type                     | Tool                                  |
| ------------------------ | ------------------------------------- |
| Unit (models, providers) | `flutter_test`                        |
| Widget tests             | `flutter_test` + `golden_toolkit`     |
| Integration              | `integration_test` package + emulator |

### Data Quality

Maintain a **golden receipt dataset**: 100 receipts with hand-verified canonical JSON. Run the parser against this set on every deploy. Alert if accuracy drops below 85%.

### Manual QA Checklist (before each phase release)

- [ ] Upload 5 receipts from different stores and verify parsing
- [ ] Confirm analytics totals match manual sum of receipts
- [ ] Test offline mode: no internet, then reconnect
- [ ] Test auth token expiry and refresh
- [ ] Verify RLS: two test accounts cannot see each other's data

---

## 15. Performance & Scalability

### Targets

| Metric                      | Target             |
| --------------------------- | ------------------ |
| Receipt upload to processed | < 30 seconds (P95) |
| Dashboard load (cached)     | < 500ms            |
| Bill list (first page)      | < 800ms            |
| Search response             | < 1 second         |
| API error rate              | < 0.1%             |

### Optimisations

- **Analytics cache**: pre-computed on receipt insert, served from `analytics_cache` table (or Redis)
- **Pagination**: all list endpoints cursor-paginated (no OFFSET)
- **DB indexes**: on `user_id`, `date`, `name_normalised`, `store_id`, and composite indexes for common filter patterns
- **Image compression**: Flutter compresses images to ≤2MB before upload (quality 85%)
- **OCR batching**: if user uploads multiple images at once, OCR jobs are batched
- **CDN**: Supabase Storage served via CDN; image URLs cached on Flutter client

### Scaling Path

The current architecture scales vertically (bigger Supabase plan + more Celery workers) to handle thousands of users. For 100k+ users, the natural evolution is:

- Read replicas for analytics queries
- Separate microservice for the OCR/parsing pipeline
- Kafka replacing Celery for the pipeline queue
- Partitioned `receipt_items` table by `user_id` hash

---

## 16. Risk Register

| Risk                                         | Likelihood | Impact | Mitigation                                                                                          |
| -------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------------------------------- |
| OCR accuracy poor on crumpled/faded receipts | High       | High   | Image pre-processing; manual correction UI; low-confidence flagging                                 |
| OCR provider cost overrun                    | Medium     | High   | Rate limit uploads; compress images; cache OCR results; evaluate cheaper providers                  |
| Product name normalisation mismatches        | High       | Medium | Fuzzy matching; user corrections feed back into alias table                                         |
| Supabase free-tier limits hit                | Medium     | Medium | Monitor usage; upgrade plan proactively; archive old analytics                                      |
| Flutter state complexity grows unmanageable  | Medium     | Medium | Strict Riverpod layering from day one; code reviews gate provider sprawl                            |
| AI layer hallucinations in Q&A               | Medium     | Medium | Ground responses in structured data; show source receipts; add disclaimer                           |
| App rejected from app stores                 | Low        | High   | Follow Play Store / App Store guidelines; avoid storing sensitive financial data without disclosure |
| Receipt image contains PII beyond scope      | Low        | Medium | Store images only in user-scoped private bucket; never expose raw URLs publicly                     |

---

_This document is the single source of truth for the Grocery Bill Intelligence App production build. Update it as decisions are made and phases are completed._
