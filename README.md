# Chessing

A full-stack chess app with real-time multiplayer, offline Stockfish bots, and
post-game analysis — built to explore real-time state synchronization,
reconnection-safe game state, and concurrency-correct DB writes.

**Cross-platform Flutter client + Bun/Elysia backend + MongoDB.**

---

## What it does

- **Quick Play** — online matchmaking, auto-matched by time control (bullet /
  blitz / rapid / classical — 1, 3, 5, 10, 15, 30 min).
- **Play with Friends** — create a private game, share the 6-digit code.
- **Play vs Bot** — 5 difficulty levels (~800–1600 ELO) running Stockfish
  locally in a background isolate, so the UI never stalls.
- **Post-game analysis** — Stockfish evaluation of every move with
  classifications (brilliant / great / good / inaccuracy / mistake / blunder)
  and per-player accuracy.
- **Real-time everything** — moves, clocks, draw offers, resigns, disconnects
  all sync over WebSocket.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Mobile App (Flutter)               │
├─────────────────────────────────────────────────┤
│  Screens            Providers         Services  │
│  - Home             AuthProvider      ApiService│
│  - Login            GameProvider      SocketService
│  - Game                               BotService (isolate)
│  - Analysis                           Audio / Vibration
└─────────────────┬───────────────────────────────┘
                  │  REST + WebSocket
                  ▼
┌─────────────────────────────────────────────────┐
│           Backend (Bun + Elysia + TS)           │
├─────────────────────────────────────────────────┤
│  WS handlers     GameManager      RatingService │
│  - MOVE          - matchmaking    - Glicko-2    │
│  - RESIGN        - time control                 │
│  - DRAW          - reconnection                 │
│  - QUEUE         - server-side                  │
│                    move validation              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│               MongoDB Atlas                     │
│   users · games (with analysis subdocument)     │
└─────────────────────────────────────────────────┘
```

---

## Tech stack

### Mobile (`real_chess_mobile/`)

| Area          | Choice                                              |
|---------------|-----------------------------------------------------|
| Framework     | Flutter 3.x (Dart)                                  |
| State         | `provider` (ChangeNotifier)                         |
| Chess engine  | `chess` package (client-side legality + SAN)        |
| Board         | Custom widget (`custom_chess_board.dart`) with SVG pieces (`chess_vectors_flutter`), Chess.com green theme |
| Networking    | `web_socket_channel` + `http`                       |
| Audio/Haptics | `audioplayers`, platform haptics                    |
| Bot AI        | Minimax + α-β pruning, 1–5 ply, runs in isolate    |

### Backend (`chess-backend/`)

| Area          | Choice                                              |
|---------------|-----------------------------------------------------|
| Runtime       | Bun                                                 |
| Framework     | Elysia.js (with CORS)                               |
| WebSocket     | Native Bun WS at `/ws`                              |
| Database      | MongoDB Atlas via Mongoose                          |
| Auth          | JWT — server **refuses to start** without `JWT_SECRET` |
| Password hash | bcryptjs                                            |
| Chess engine  | Stockfish.js (ASM.js build, Bun-compatible)         |
| Chess logic   | `chess.js` for server-side move validation          |
| Rating        | Glicko-2 (`src/services/ratingService.ts`)          |

---

## Notable technical decisions

These are the things I'd actually want to talk about in an interview — the
non-obvious calls that shaped the app.

### 1. Server-side move validation, with `playerId` derived only from JWT

The client uses `chess.dart` for instant local validation (UX), but the
**server re-validates every move** against its own `chess.js` game state
before broadcasting. The player's identity is pulled from the JWT claim,
never from anything the client sends — a client that lies about "I'm the
white player" gets rejected at the auth middleware.

### 2. MongoDB atomic operators for concurrency correctness

Game state has multiple writers (both players + the server timer). In-memory
state + naïve writes would race. All numeric updates to game state use
MongoDB's `$max` / `$min` operators so the DB — not stale in-memory values —
decides the winner in a concurrent update. This is what you want when
two simultaneous WebSocket frames try to update the same game.

### 3. Reconnection with grace period and exponential backoff

Mobile networks drop. The app treats disconnects as suspensions, not forfeits:

- **Client** retries with exponential backoff: 1s → 2s → 4s → 8s → 16s (up to 5).
- **Server** keeps the game alive for a **60-second grace period** before
  declaring forfeit. Game state is recovered from MongoDB on reconnect.
- **Opponent UI** shows a connection-status dot (green/yellow/red) during
  the grace period so they know what's happening instead of staring at
  a frozen board.

### 4. Bot runs in a background isolate

Minimax with α-β pruning at 5 plies is not free on a phone. Running it on
the UI thread would freeze the board during bot "thinking". Bot moves
execute in a Dart isolate and post results back — UI stays at 60 fps even
at the highest difficulty.

### 5. Glicko-2 instead of flat Elo

Rating uses Glicko-2 (with rating deviation and volatility) rather than
a simple +10/−10 Elo. Stored per-user with full rating history for charts
and peak rating.

### 6. Custom chess board widget

Using a pre-built board widget created overflow issues on small screens
and locked-in rendering choices I didn't want. The custom widget
(`custom_chess_board.dart`) gives me control over piece rendering
(SVG, not Unicode glyphs — sharper on all DPIs), theming
(`#EBECD0` / `#779556`), and interaction
(drag-and-drop + tap-to-move + legal-move dots + capture rings +
last-move highlight).

---

## Project structure

```
chess-mobile/
├── chess-backend/
│   ├── src/
│   │   ├── index.ts                # Server entry, WebSocket handlers, REST routes
│   │   ├── GameManager.ts          # Game state, move validation, matchmaking, timers
│   │   ├── middleware/authMiddleware.ts  # JWT verification
│   │   └── services/ratingService.ts     # Glicko-2 calculations
│   ├── stockfish.wasm
│   ├── package.json
│   └── tsconfig.json
├── real_chess_mobile/
│   └── lib/
│       ├── main.dart
│       ├── api/              # REST endpoints
│       ├── providers/        # AuthProvider, GameProvider
│       ├── services/         # Socket, Bot (isolate), Audio, Vibration, Network
│       ├── screens/          # Home, Login, Game, Analysis
│       ├── widgets/          # custom_chess_board.dart, etc.
│       ├── models/
│       └── utils/            # config.dart (server IP)
├── CHESSING_APP_DOCUMENTATION.md  # Full feature + API reference
└── PROGRESS.md
```

---

## WebSocket events

**Client → Server:** `CREATE_GAME · JOIN_GAME · QUEUE_MATCH · CANCEL_QUEUE ·
MOVE · RESIGN · OFFER_DRAW · ACCEPT_DRAW · DECLINE_DRAW`

**Server → Client:** `GAME_CREATED · GAME_JOINED · QUEUED · MATCH_FOUND ·
QUEUE_TIMEOUT · MOVE_MADE · GAME_OVER · DRAW_OFFERED · DRAW_DECLINED ·
OPPONENT_DISCONNECTED · OPPONENT_RECONNECTED · ERROR`

Full schemas in [`CHESSING_APP_DOCUMENTATION.md`](./CHESSING_APP_DOCUMENTATION.md).

---

## Running locally

### Prerequisites

- Flutter SDK 3.x
- Bun runtime (`curl -fsSL https://bun.sh/install | bash`)
- A MongoDB instance (local or Atlas)

### 1. Backend

```bash
cd chess-backend
bun install

# Required
export JWT_SECRET="some-long-random-string"
export MONGO_URI="mongodb+srv://..."

bun run dev   # server listens on :8080, WebSocket at /ws
```

The server **will refuse to start without `JWT_SECRET`** — this is
intentional (no fallback secret in production).

### 2. Mobile app

```bash
cd real_chess_mobile
flutter pub get
flutter run
```

If you're running the backend locally and testing on an Android emulator,
set the server IP to `10.0.2.2` in `lib/utils/config.dart`. For a physical
device, use your machine's LAN IP (default placeholder: `192.168.1.115`).

---

## Status

Active development. See [`CHESSING_APP_DOCUMENTATION.md`](./CHESSING_APP_DOCUMENTATION.md)
for the full feature matrix (what's shipped, what's in progress, what's
roadmapped) and [`PROGRESS.md`](./PROGRESS.md) for recent work.

---

## What I'd do differently in v2

- **Move the bot off minimax to Stockfish on-device.** The current minimax
  implementation is fine for ~1600 ELO but won't scale to stronger play.
  Stockfish-wasm in a Flutter isolate would be stronger and simpler.
- **Add an opening book and endgame tablebase** — both for the bot and for
  analysis. Current post-game analysis feels hollow in the opening since
  every move evaluates similarly.
- **Replace the +/- ELO-style adjustments that surround Glicko-2** with a
  cleaner inflow → Glicko-2 → store pipeline. Currently there are a couple
  of adjustment paths that should be unified.
- **Observability.** Zero structured logging on the backend right now.
  Would add pino + request IDs threaded through WebSocket events.
