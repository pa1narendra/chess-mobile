# Chessing - Chess Mobile App

## Project Structure

```
chess-mobile/
  chess-backend/       # Bun + Elysia.js + MongoDB Atlas (port 8080)
  real_chess_mobile/   # Flutter + Provider state management
```

### Backend Stack
- **Runtime**: Bun
- **Framework**: Elysia.js with CORS
- **Database**: MongoDB Atlas via Mongoose
- **Auth**: JWT (mandatory JWT_SECRET env var — server refuses to start without it)
- **Chess Engine**: Stockfish.js (ASM.js version for Bun compatibility)
- **WebSocket**: Native Bun WS at `/ws`

### Frontend Stack
- **Framework**: Flutter (Dart)
- **State**: Provider (ChangeNotifier pattern)
- **Board**: CustomChessBoard widget (`lib/widgets/custom_chess_board.dart`)
- **Pieces**: chess_vectors_flutter (SVG vectors, NOT Unicode text)
- **Board Theme**: Chess.com green (`#EBECD0` light / `#779556` dark)
- **Real-time**: web_socket_channel

## Clean Code Rules

### Flutter / Dart

1. **Every `Row` with `Text` children** must wrap text in `Flexible` or `Expanded` with `overflow: TextOverflow.ellipsis` and `maxLines: 1`
2. **Every dialog with 4+ list items** must use `ListView(shrinkWrap: true)` — never `Column` (causes overflow on small screens)
3. **Every `TextEditingController`** created in dialogs must be disposed via `try/finally`
4. **No empty catch blocks** — at minimum use `debugPrint('[Context] error: $e')`
5. **No unused model files, methods, or imports** — delete dead code immediately
6. **No duplicate assignments** — check for accidental copy-paste of state updates
7. **No `SingleChildScrollView` wrapping a `Column` that contains `Expanded`** — this causes zero-height collapse. Use `Flexible(flex: 0)` for shrinkable sections instead
8. **All long content areas** (game-over overlays, analysis results) must be scrollable
9. **Use `chess.san_moves()`** to get SAN notation — `chess.history` returns `List<State>` objects, not strings

### TypeScript / Backend

1. **Every `ws.send()`** must use `JSON.stringify()` — never send raw objects
2. **Every `async` function call** must be `await`ed if the return value is used — missing await returns a Promise object, not the result
3. **All DB writes** in GameManager must use `await` with error handling (`.catch()` at minimum)
4. **Use MongoDB `$max`/`$min` operators** for atomic comparisons — never compare against stale in-memory values
5. **Derive `playerId` from JWT only** — never trust client-provided IDs
6. **No `console.log` with sensitive data** (passwords, full tokens, connection strings)
7. **Game schema enums must match all values used in code** — check `winner` and `reason` enums when adding new game-over reasons

## Progress Tracking

When implementing a feature with 3+ steps, show progress:
```
[40%] Building game history screen (2/5 steps done)
```
Update after each completed step.

## Testing Checklist (before any commit)

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` — 0 errors
- [ ] Backend starts clean: `bun run dev` then `curl localhost:8080/health`
- [ ] No overflow warnings on small screens (320px wide)
- [ ] Moves work in multiplayer (both players see updates)
- [ ] Bot games respond correctly
- [ ] No `print()` or `console.log()` with sensitive data

## Key Files

| File | Purpose |
|------|---------|
| `chess-backend/src/index.ts` | Server entry, WebSocket handlers, REST routes |
| `chess-backend/src/GameManager.ts` | Game state, move validation, timers, matchmaking |
| `chess-backend/src/middleware/authMiddleware.ts` | JWT verification (shared across routes) |
| `chess-backend/src/services/ratingService.ts` | Glicko-2 rating calculations |
| `real_chess_mobile/lib/widgets/custom_chess_board.dart` | Chess board widget (green theme, SVG pieces) |
| `real_chess_mobile/lib/providers/game_provider.dart` | Game state, socket events, offline bot |
| `real_chess_mobile/lib/providers/auth_provider.dart` | Auth state, token management |
| `real_chess_mobile/lib/screens/analysis_screen.dart` | Post-game analysis with eval bar |

## Environment

- Default server IP: `192.168.1.115` (configurable in `lib/utils/config.dart`)
- Backend port: `8080`
- MongoDB database: `RealChess`
- NDK version: `28.2.13676358`
