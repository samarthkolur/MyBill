# MyBill — Flutter app

The MyBill mobile client. Architecture and roadmap live in [`../MyBill.md`](../MyBill.md);
build status in [`../DESIGN.md`](../DESIGN.md).

## Configuration

Config is injected at build time with `--dart-define` — nothing secret is committed.

| Define              | Required | Default                    | Notes                                 |
| ------------------- | -------- | -------------------------- | ------------------------------------- |
| `SUPABASE_URL`      | yes      | —                          | `https://<project>.supabase.co`       |
| `SUPABASE_ANON_KEY` | yes      | —                          | Anon/publishable key (safe in client) |
| `API_BASE_URL`      | no       | `http://localhost:8000/v1` | FastAPI backend base URL              |

The app throws a `StateError` on boot if the Supabase defines are missing, rather than
failing later inside the SDK.

## Running

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

The Supabase values are the same ones the backend uses — see `backend/.env`.

> Android emulator note: `localhost` is the emulator itself, so reach a host-machine
> backend via `--dart-define=API_BASE_URL=http://10.0.2.2:8000/v1`.

## Tests & checks

```sh
flutter analyze
flutter test
```

## Architecture

```
lib/
├── app.dart                    MaterialApp.router + theme
├── main.dart                   Supabase init, then runApp
├── core/
│   ├── constants/              build-time config
│   ├── router/                 GoRouter + the auth guard
│   ├── storage/                Supabase session → platform keystore
│   ├── theme/                  Material 3 theme
│   └── utils/                  form validators
└── features/<feature>/
    ├── application/            Riverpod controllers (state)
    ├── data/                   repositories (I/O)
    └── presentation/           screens + widgets
```

### Auth

Authentication is **client-to-Supabase**: the app signs in against Supabase Auth directly
and sends the resulting JWT to the backend, which only verifies it
(`backend/app/core/security.py`) — the backend issues no credentials of its own.

- Sessions (access **and** refresh token) persist to the platform keystore via
  `SecureLocalStorage`, not the SDK's default plain-text `SharedPreferences`.
- `AuthController` mirrors the SDK's `onAuthStateChange` stream, so background refreshes
  and expiries are reflected app-wide.
- Route protection is a single `redirect` rule in `core/router/app_router.dart`: new
  routes are **protected by default** and must opt into `AppRoutes.unauthenticated` to be
  reachable while signed out. Screens never navigate on sign-in/sign-out — they change
  auth state and the guard reacts.

#### Password reset — not yet end-to-end

The Forgot Password screen sends Supabase's recovery email, but tapping the link does not
yet return to the app: the `io.mybill.app://reset-password` scheme is not registered in
the Android manifest / iOS `Info.plist`, and there is no screen to set the new password.
Completing that flow is outstanding work.
