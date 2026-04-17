# Chessing — Progress Report

_Last updated: 2026-04-04_

## Project Summary

Chess mobile app with Flutter frontend + Bun/Elysia.js backend + MongoDB Atlas.
Two-player real-time chess over WebSocket, offline bot play, full analysis with Stockfish, Glicko-2 rating system, friends, challenges, puzzles, and more.

---

## What We've Built So Far

### Core Gameplay
- **Quick Play** — Rating-based matchmaking with expanding window (±100 → ±200 → ±400 → ±800 → any over 30s)
- **Play vs Bot** — Offline, 5 difficulty tiers, runs locally via chess.js minimax
- **Play with Friends** — Create private game with 6-digit code, time control selection (1/3/5/10/15/30 min)
- **Rematch** — Post-game rematch request with swapped colors
- **Challenge Friend** — Direct challenge with time control picker, 60s expiration, accept/decline flow
- **Abort** — In first 2 moves, "Resign" becomes "Abort" with no rating loss
- **Anti-farming** — Matchmaking tracks last 3 opponents to reduce repeat matches
- **Fallback matching** — If only 2 players queued, match regardless of rating

### Time Controls
- 1 min (Bullet), 3 min (Blitz), 5 min (Blitz), 10 min (Rapid), 15 min (Rapid), 30 min (Classical)
- Time sync between devices via server-authoritative `lastMoveTime` + `timeRemaining` broadcasts

### Analysis
- **Post-game Stockfish analysis** — Full evaluation per move
- **Eval bar** — Visual white/black advantage indicator at current position
- **Move classifications** — Brilliant, great, good, inaccuracy, mistake, blunder (color-coded dots)
- **Accuracy per player** — White vs Black accuracy percentage
- **Move-by-move replay** — Navigate through all positions with fast-forward buttons
- **Key Moments navigator** — Jump directly to next/previous blunder/mistake/brilliant
- **Opening Explorer** — Toggle to view master games reaching current position (via Lichess Masters API)
- **PGN export** — Share full game as PGN via native share sheet or clipboard

### Post-Game Experience
- **Modal overlay** showing Victory/Defeat/Draw with reason
- **Rating change** displayed with up/down arrow and +/- value
- **Action buttons**: Analyze, Rematch, Home
- Resign/Draw menu automatically hidden after game ends

### Social Features
- **Friends system** — Search users, send/accept/decline friend requests, remove friends
- **Online status** — Green dot indicator on friend cards
- **Friend challenges** — Challenge a friend directly with time control selection
- **In-game chat** — Real-time chat during active games
  - Chess.com-style message bubbles (teal for you, dark for opponent)
  - Emoji picker integrated into text input
  - Sender name + timestamp
  - Unread count badge in AppBar
  - Profanity filter
  - 200 char limit
  - Chat disabled after game over
- **Only allowed for friend/multiplayer games** — not in bot games

### Puzzles
- **Daily puzzle** (same for all users via Lichess daily endpoint)
- **Random puzzles** with difficulty selection
- **Rating system** — Glicko-like K-factor adjustment based on puzzle rating vs user rating
- **Stats tracking** — Solved, failed, current streak, best streak
- **Auto-play opponent response** after correct user move
- **Show solution** button for when stuck
- **Theme tags** displayed (fork, pin, mate-in-2, etc.)
- Sources ~4M puzzles via Lichess public API — no DB seeding needed

### User Profile & Stats
- **Glicko-2 rating system** — Replaces naive +10/-10 ELO with proper Glicko-2 calculation
- **Rating history chart** (last 30 data points, custom painter)
- **Peak rating** — Tracked atomically via MongoDB `$max` operator
- **Stats** — Games played, wins, losses, draws, win rate, current streak, best streak
- **Editable profile** — Display name, bio, country code
- **Rank calculation** — Global rank by rating
- **Recent games count** — Last 30 days

### Leaderboard
- **Global leaderboard** sorted by rating
- **Gold/silver/bronze medals** for top 3
- **Rating badge** with teal accent
- **Win rate + games played** display
- **Pagination** support

### Game History
- **Past games list** with infinite scroll
- **Win/loss/draw indicators** with color coding
- **Opponent name**, bot badge, move count, accuracy (if analyzed)
- **Tap to open** detail screen with board replay
- **Analyze button** per game card (navigates to Analysis screen)

### Chess Board UI
- **Custom chess board widget** (`CustomChessBoard`) replacing the package default
- **Chess.com green theme** (#EBECD0 light / #779556 dark)
- **SVG vector pieces** from `chess_vectors_flutter` with proper styling
- **Coordinate labels** — Rank numbers on left column, file letters on bottom row
- **Drag and drop** — Only own-turn pieces are draggable
- **Double-validation** — Drop target rejects wrong-color moves
- **Enlarged drag feedback** (1.2x)

### Infrastructure
- **JWT authentication** — Mandatory `JWT_SECRET` env var, no weak fallback
- **Rate limiting** — 60 messages/minute per WebSocket connection
- **CORS restriction** — Configurable origin
- **Input validation** — Square format, promotion, gameId on all WebSocket messages
- **Player identity from JWT only** — No client-provided playerId trusted
- **MongoDB injection protection** — Operator blacklist + stage whitelist in search service
- **Auth middleware** — All `/search/*` and `/api/*` routes protected
- **Atomic `$max`/`$min` operators** for peak rating and best streak
- **Shared JWT middleware** — Extracted to `middleware/authMiddleware.ts`
- **Health endpoint** — `/health` returns status + uptime

---

## Bugs Fixed (Major)

1. **Chat silent failure** — `joinGame` updated DB but not in-memory `game.status`, so chat handler's `status === 'active'` check silently rejected all messages in friend games
2. **Missing `await` on async `makeMove`** — `makeMove` was async but called without `await`, causing every move to return "Invalid move" and time desync
3. **`Object.assign` bug** — White name was never set when creating a game
4. **Rate limit error sent as raw object** — Missing `JSON.stringify()`
5. **`moves.map(m => m.san)` bug** — moves are UCI strings, not objects; caused `undefined` history
6. **Peak rating stale value** — Math.max used pre-fetched data; replaced with MongoDB `$max`
7. **Stats showing 0** — Migration from flat `gamesPlayed` to nested `stats.games` + fallback logic
8. **Duplicate game-over broadcasts** — Removed redundant handling in `onMove` callback
9. **Duplicate `_currentTurn` assignment** — Accidental copy-paste
10. **Silent catch block in refreshUser** — Added debugPrint
11. **TextEditingController leaks** — Added try/finally dispose in login dialogs
12. **Redundant `_loadProfile` call** — `refreshUser` already fetches data

---

## Architecture

```
chess-mobile/
├── chess-backend/                  # Bun + Elysia.js, port 8080
│   └── src/
│       ├── index.ts                # Server entry, WebSocket handlers
│       ├── GameManager.ts          # Game state, move validation, matchmaking
│       ├── BotManager.ts           # Stockfish integration for bot + analysis
│       ├── auth.ts                 # Login/register/me endpoints
│       ├── db.ts                   # MongoDB connection
│       ├── middleware/
│       │   └── authMiddleware.ts   # Shared JWT verification
│       ├── routes/
│       │   ├── apiRoutes.ts        # REST endpoints (games, friends, puzzles, profile)
│       │   └── searchRoutes.ts     # Generic search (protected)
│       ├── services/
│       │   ├── SearchService.ts    # MongoDB aggregation with injection protection
│       │   └── ratingService.ts    # Glicko-2 calculation
│       └── schemas/
│           ├── user.ts             # User + profile + stats + rating
│           ├── game.ts             # Game + analysis + result
│           ├── friendship.ts       # Friend requests + relationships
│           └── puzzleProgress.ts   # Puzzle rating + streaks
│
└── real_chess_mobile/              # Flutter + Provider
    └── lib/
        ├── main.dart               # App theme (AppColors)
        ├── api/
        │   ├── api_service.dart    # HTTP REST client
        │   └── socket_service.dart # WebSocket client with reconnection
        ├── providers/
        │   ├── auth_provider.dart  # Token + user state
        │   └── game_provider.dart  # Game state + chat + rematch + challenges
        ├── screens/
        │   ├── home_screen.dart
        │   ├── login_screen.dart
        │   ├── game_screen.dart         # Active game + overlay + chat sheet
        │   ├── game_detail_screen.dart  # View past game with board replay
        │   ├── game_history_screen.dart
        │   ├── analysis_screen.dart     # Stockfish analysis + explorer + key moments
        │   ├── leaderboard_screen.dart
        │   ├── profile_screen.dart
        │   ├── friends_screen.dart      # Tabs: Friends / Requests / Sent
        │   └── puzzles_screen.dart      # Daily + random puzzles
        ├── widgets/
        │   ├── custom_chess_board.dart  # Green theme, SVG pieces
        │   └── custom_button.dart
        └── services/
            ├── audio_service.dart
            ├── bot_service.dart         # Offline bot (minimax)
            ├── error_service.dart
            ├── network_service.dart
            └── vibration_service.dart
```

---

## Recently Completed (Today's Session)

### Session 1: Core Features
- Added rating-based matchmaking with expanding window and anti-farming
- Built Rematch feature (WebSocket events + bottom sheet button)
- Built Friends system (schema, REST endpoints, search + list + tabs screen)
- Fixed `Object.assign` bug in white name setting
- Fixed rate limit error missing `JSON.stringify()`
- Removed duplicate game-over broadcast
- Simplified streak calculation with helper function

### Session 2: S-Tier Feature Batch
From the feature report recommendations, completed all 5 S-tier items:
1. **PGN export/share** — Share button with full PGN headers
2. **Abort in first 2 moves** — No rating loss for early aborts
3. **Opening Explorer** — Lichess Masters API integration
4. **Key Moments Navigator** — Jump between blunders/mistakes in analysis
5. **Puzzles** — Daily + random puzzles with rating tracking

---

## What's Next

Pulled from the feature report at `C:\Users\pavan\.claude\plans\dreamy-stargazing-globe.md`.

### Do Next (Tier A — High value, moderate effort)

- [ ] **Personality bots** — Give bots names, avatars, and playstyles (aggressive/positional/blundery) instead of just difficulty tiers. Chess.com's Streamer Bots are their most-used feature.
- [ ] **Accuracy graph** — Line chart showing eval per move across the whole game (data already computed from analysis)
- [ ] **Coordinate trainer** — Click the named square as fast as possible. Lichess staple, teaches board vision
- [ ] **Move sound differentiation** — Different sounds for capture, check, castle, promote, game over (audio service already exists)
- [ ] **Multi-PV in analysis** — Show top 2-3 engine lines instead of just best move
- [ ] **Spectator mode** — Watch live games of friends via WebSocket subscribe mechanism

### Do Later (Tier B — Nice-to-have)

- [ ] **Time increments (Fischer)** — `3+2`, `5+3` formats
- [ ] **Premove** — Queue your move while opponent is thinking
- [ ] **Board themes** — Multiple color options (green, brown, blue, purple)
- [ ] **Piece themes** — Swap between piece styles
- [ ] **Daily login streak + XP** — Gamification layer
- [ ] **Push notifications** — Needed for challenges and friend requests

### Novel Differentiators (from the report)

- [ ] **"Why did I lose?" one-sentence summary** — Glanceable TL;DR post-game
- [ ] **"Explain this move" live hint** — Unique to our app, only in untimed bot games
- [ ] **Rematch with handicap** — Piece or time handicap for uneven-skill friends
- [ ] **Trash Talk Mode** — Pre-baked reaction emojis (no free chat to avoid toxicity)
- [ ] **Speedrun mode** — Fresh Glicko rating, leaderboard for 800→2000 climbs
- [ ] **Timezone-aware tournaments** — Schedule by local time instead of UTC

### Park For Now

- Clubs/teams
- Correspondence / daily games
- Shared puzzle library with friends
- Live shared analysis ("Study this game together")

### Never Do (from the report)

- Chess variants (splits small playerbase)
- Cheat detection / anti-cheat ML (needs dedicated team)
- Video lessons / GM content (licensing costs)
- Twitch streaming integration (need streamers first)
- Blockchain / NFT chess (universally rejected)
- Ultrabullet (<1 min) (latency kills playability)
- Engine strength slider (non-linear curve feels broken)
- Public game chat with strangers (toxicity)
- User-uploaded piece sets (moderation nightmare)
- Global voice chat (expensive + moderation)
- Gambling / wagering (regulatory risk, app store ban)
- AI-generated coaching via LLM (hallucinates illegal moves)
- Country-separated leaderboards (sparse data)

---

## Testing Checklist

Before any commit, verify:

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` shows 0 errors
- [ ] Backend starts clean: `bun run dev` then `curl localhost:8080/health`
- [ ] Quick Play works between two accounts
- [ ] Bot game responds correctly
- [ ] Chat messages send and receive
- [ ] Friend request flow end-to-end
- [ ] Challenge flow (send → accept → play)
- [ ] Puzzle daily + random load and play through
- [ ] Opening Explorer fetches master games
- [ ] PGN share opens native share sheet
- [ ] No overflow warnings on small screens (test 320px width)
- [ ] Rebuild on physical device works

---

## Known Issues / Technical Debt

1. **Hardcoded default IP** — `config.dart` has `_defaultIp = "192.168.1.115"`. Should be configurable on first launch
2. **`GameProvider` is 1500+ lines** — Should split into `GameEngineProvider`, `SocketGameProvider`, `ChatProvider`, `ChallengeProvider`
3. **No push notifications** — Required for friend requests, challenges, and correspondence chess
4. **Tokens in SharedPreferences** — Should use `flutter_secure_storage` for sensitive data
5. **Analysis is synchronous** — Evaluating 50 positions can take minutes; should be a background job with streaming progress
6. **No soft delete** — Deleted games/users are gone forever
7. **Matchmaking O(n)** — Linear queue scan; won't scale past ~1000 concurrent players
8. **No certificate pinning** — MITM attacks possible
9. **Abandoned games cleanup** — 1 hour threshold; should be configurable
10. **No offline game persistence** — Bot games are lost on app crash

---

## Key Constants & Defaults

| Setting | Value | Location |
|---------|-------|----------|
| Backend port | 8080 | `chess-backend/src/index.ts` |
| Default matchmaking timeout | 30s | `GameManager.ts:41` |
| Disconnection grace period | 60s | `GameManager.ts:42` |
| Rating window (start) | ±100 | `getRatingWindow()` |
| Rating window (max fallback) | 30s+ any | `getRatingWindow()` |
| WebSocket rate limit | 60/min | `index.ts:checkRateLimit()` |
| Chat message max | 200 chars | `index.ts:CHAT_MESSAGE handler` |
| Challenge expiration | 60s | `index.ts:CHALLENGE_REQUEST handler` |
| Default rating | 1200 | User schema |
| Rating deviation (new) | 350 | Glicko-2 default |
| Anti-farming history | Last 3 opponents | `GameManager.ts:recentOpponents` |
| JWT expiration | 7 days | `auth.ts` |
| Abandoned game cleanup | 1 hour | `GameManager.ts:cleanupAbandonedGames` |
| Finished game in-memory TTL | 1 hour | `GameManager.ts:handleGameOver` |

---

## Tech Stack

### Backend
- **Runtime**: Bun
- **Framework**: Elysia.js
- **Database**: MongoDB Atlas (Mongoose ODM)
- **Chess engine**: Stockfish.js (ASM.js build for Bun compat)
- **Auth**: JWT (jsonwebtoken)
- **Password**: Bun.password (bcrypt)

### Frontend
- **Framework**: Flutter 3.41
- **State**: Provider (ChangeNotifier)
- **Chess logic**: `chess` package + `flutter_chess_board` controller
- **Pieces**: `chess_vectors_flutter` (SVG)
- **WebSocket**: `web_socket_channel`
- **HTTP**: `http`
- **Local storage**: `shared_preferences`
- **Emojis**: `emoji_picker_flutter`
- **Share**: `share_plus`
- **Audio**: `audioplayers`

---

## References

- Feature report: `C:\Users\pavan\.claude\plans\dreamy-stargazing-globe.md`
- Clean code rules: `CLAUDE.md` (project root)
- Lichess API (puzzles/explorer): https://lichess.org/api
- Glicko-2 paper: http://www.glicko.net/glicko/glicko2.pdf
