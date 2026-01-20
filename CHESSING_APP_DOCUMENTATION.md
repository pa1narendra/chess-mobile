# Chessing - Chess Application Documentation

> A full-featured, real-time multiplayer chess application with AI opponents, game analysis, and modern UI/UX.

---

## Table of Contents

1. [Overview](#overview)
2. [Tech Stack Summary](#tech-stack-summary)
3. [Architecture](#architecture)
4. [Implemented Features](#implemented-features)
5. [Feature Details](#feature-details)
6. [Areas for Improvement](#areas-for-improvement)
7. [Future Roadmap](#future-roadmap)
8. [Technical Stack (Detailed)](#technical-stack-detailed)

---

## Overview

**Chessing** is a cross-platform chess application that allows users to:
- Play chess online against real players with matchmaking
- Challenge friends using private game codes
- Practice against AI bots with 5 difficulty levels
- Analyze completed games with engine evaluation
- Track their rating and game statistics

The app features real-time gameplay, reconnection handling, audio/haptic feedback, and a modern dark-themed UI.

---

## Tech Stack Summary

### Frontend (Mobile App)
| Technology | Purpose |
|------------|---------|
| **Flutter 3.x** | Cross-platform UI framework |
| **Dart** | Programming language |
| **Provider** | State management |
| **SharedPreferences** | Local data persistence |
| **chess.dart** | Chess logic & move validation |
| **flutter_chess_board** | Interactive chess board widget |
| **audioplayers** | Sound effects playback |
| **web_socket_channel** | Real-time WebSocket communication |
| **http** | REST API calls |

### Backend (Server)
| Technology | Purpose |
|------------|---------|
| **Bun** | JavaScript/TypeScript runtime (fast) |
| **TypeScript** | Type-safe server code |
| **MongoDB** | NoSQL database |
| **Mongoose** | MongoDB ODM |
| **chess.js** | Server-side move validation |
| **Stockfish.js** | Chess engine for analysis & bot |
| **JWT** | Token-based authentication |
| **bcryptjs** | Password hashing |
| **WebSocket (native Bun)** | Real-time game sync |

### Infrastructure
| Component | Technology |
|-----------|------------|
| **Database** | MongoDB (local or Atlas) |
| **API Protocol** | REST + WebSocket |
| **Authentication** | JWT tokens |
| **Mobile Platforms** | Android, iOS |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MOBILE APP (Flutter)                      │
├─────────────────────────────────────────────────────────────┤
│  Screens          │  Providers        │  Services            │
│  - Home           │  - AuthProvider   │  - ApiService        │
│  - Login          │  - GameProvider   │  - SocketService     │
│  - Game           │                   │  - BotService        │
│                   │                   │  - AudioService      │
│                   │                   │  - VibrationService  │
│                   │                   │  - NetworkService    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ WebSocket + REST API
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   BACKEND (Bun + TypeScript)                 │
├─────────────────────────────────────────────────────────────┤
│  WebSocket Server  │  Game Manager    │  Bot Manager         │
│  - Real-time sync  │  - Game state    │  - Stockfish engine  │
│  - Reconnection    │  - Matchmaking   │  - Move calculation  │
│  - Auth validation │  - Time control  │  - Analysis          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     DATABASE (MongoDB)                       │
├─────────────────────────────────────────────────────────────┤
│  Users Collection          │  Games Collection              │
│  - Authentication          │  - Move history                │
│  - Rating & Stats          │  - Game results                │
│  - Preferences             │  - Analysis data               │
└─────────────────────────────────────────────────────────────┘
```

---

## Implemented Features

### Authentication & User Management

| Feature | Status | Description |
|---------|--------|-------------|
| User Registration | ✅ Complete | Sign up with username, email, password |
| User Login | ✅ Complete | JWT token-based authentication |
| Session Persistence | ✅ Complete | Auto-login using stored tokens |
| User Profile | ✅ Complete | Display username, rating, avatar |
| Logout | ✅ Complete | Clear session and disconnect socket |
| Cached User Data | ✅ Complete | Works across hot restarts |

### Game Modes

| Mode | Status | Description |
|------|--------|-------------|
| Quick Play | ✅ Complete | Online matchmaking with time controls |
| Play with Friends | ✅ Complete | Private games with shareable codes |
| Play vs Bot | ✅ Complete | Offline AI with 5 difficulty levels |

### Chess Gameplay

| Feature | Status | Description |
|---------|--------|-------------|
| Drag-and-Drop | ✅ Complete | Intuitive piece movement |
| Tap-to-Move | ✅ Complete | Select piece, tap destination |
| Legal Move Indicators | ✅ Complete | Visual dots for valid moves |
| Capture Indicators | ✅ Complete | Red rings for capture squares |
| Pawn Promotion | ✅ Complete | Choose piece on promotion |
| Move History | ✅ Complete | SAN notation with move numbers |
| Move Replay | ✅ Complete | Click any move to view position |
| Captured Pieces | ✅ Complete | Display with material advantage |

### Time Controls

| Feature | Status | Description |
|---------|--------|-------------|
| Multiple Options | ✅ Complete | 1, 3, 5, 10, 15, 30 minutes |
| Real-time Clock | ✅ Complete | Synced between players |
| Low Time Warning | ✅ Complete | Flashing red when <30 seconds |
| Timeout Detection | ✅ Complete | Auto-forfeit on time out |
| Untimed Games | ✅ Complete | Casual mode for bot games |

### Online Features

| Feature | Status | Description |
|---------|--------|-------------|
| Real-time Sync | ✅ Complete | WebSocket-based updates |
| Matchmaking Queue | ✅ Complete | Auto-match by time control |
| Reconnection | ✅ Complete | 60-second grace period |
| Disconnect Detection | ✅ Complete | Opponent status display |
| Connection Indicator | ✅ Complete | Visual status badge |

### Game Actions

| Feature | Status | Description |
|---------|--------|-------------|
| Offer Draw | ✅ Complete | Send/accept/decline draws |
| Resign | ✅ Complete | Forfeit with confirmation |
| Game Over Detection | ✅ Complete | Checkmate, stalemate, draw |

### Post-Game Analysis

| Feature | Status | Description |
|---------|--------|-------------|
| Engine Analysis | ✅ Complete | Stockfish evaluation |
| Move Classification | ✅ Complete | Blunder, mistake, brilliant, etc. |
| Accuracy Calculation | ✅ Complete | Percentage per player |
| Key Moments | ✅ Complete | Highlighted turning points |

### Audio & Haptics

| Feature | Status | Description |
|---------|--------|-------------|
| Move Sounds | ✅ Complete | Different for move/capture |
| Check Sound | ✅ Complete | Alert on check |
| Game Over Sound | ✅ Complete | End of game audio |
| Vibration Feedback | ✅ Complete | Light/medium/heavy patterns |

### UI/UX

| Feature | Status | Description |
|---------|--------|-------------|
| Dark Theme | ✅ Complete | Modern dark color scheme |
| Responsive Layout | ✅ Complete | Adapts to screen size |
| Animated Transitions | ✅ Complete | Smooth UI animations |
| Error Handling | ✅ Complete | User-friendly messages |
| Loading States | ✅ Complete | Progress indicators |

---

## Feature Details

### 1. Quick Play (Online Matchmaking)

Players can find opponents automatically based on their preferred time control.

**How it works:**
1. User selects a time control (1-30 minutes)
2. System adds user to matchmaking queue
3. When another player with same time control joins, match is created
4. Colors are randomly assigned
5. Game begins with real-time synchronization

**Time Controls Available:**
- Bullet: 1 minute
- Blitz: 3 minutes, 5 minutes
- Rapid: 10 minutes, 15 minutes
- Classical: 30 minutes

**Queue Features:**
- 30-second timeout with notification
- Cancel queue option
- Visual queue status indicator

---

### 2. Play with Friends

Create private games and share a code with friends.

**Creating a Game:**
1. Select "Create Game"
2. Choose time control
3. Share the 6-digit game code
4. Wait for friend to join

**Joining a Game:**
1. Select "Join Game"
2. Enter the 6-digit code
3. Game starts immediately

---

### 3. Play vs Bot (AI Opponent)

Practice against a local AI with adjustable difficulty.

**Difficulty Levels:**

| Level | Name | Search Depth | Randomness | Strength |
|-------|------|--------------|------------|----------|
| 1 | Beginner | 1 ply | 40% | ~800 ELO |
| 2 | Easy | 2 plies | 25% | ~1000 ELO |
| 3 | Medium | 3 plies | 10% | ~1200 ELO |
| 4 | Hard | 4 plies | 5% | ~1400 ELO |
| 5 | Expert | 5 plies | 0% | ~1600 ELO |

**AI Features:**
- Minimax algorithm with alpha-beta pruning
- Position evaluation using piece values
- Runs in background isolate (no UI lag)
- Instant response for lower difficulties

---

### 4. Move System

**Drag-and-Drop:**
- Press and hold a piece
- Drag to destination square
- Release to complete move

**Tap-to-Move:**
- Tap a piece to select it
- Legal moves are highlighted
- Tap a highlighted square to move
- Tap elsewhere to deselect

**Visual Feedback:**
- Blue highlight: Selected piece
- Green dots: Legal move squares
- Red rings: Capture squares
- Yellow highlight: Last move

---

### 5. Game Analysis

After a game ends, analyze your play with engine assistance.

**Analysis Provides:**
- Centipawn evaluation for each position
- Best move suggestions
- Move classifications:
  - Brilliant (!!): Exceptional move
  - Great (!): Strong move
  - Good: Solid move
  - Inaccuracy (?!): Slight error
  - Mistake (?): Clear error
  - Blunder (??): Serious error

**Statistics:**
- Overall accuracy percentage
- Blunder/mistake/inaccuracy count
- Key moments in the game

---

### 6. Connection Handling

**Reconnection System:**
- Automatic reconnection attempts (up to 5)
- Exponential backoff (1s, 2s, 4s, 8s, 16s)
- 60-second grace period for disconnections
- Game state recovery on reconnect

**Status Indicators:**
- Green dot: Connected
- Yellow dot: Connecting/Reconnecting
- Red dot: Disconnected

---

## Areas for Improvement

### High Priority

| Area | Current State | Improvement |
|------|---------------|-------------|
| **Bot AI** | Pure minimax only | Add opening book and endgame tables |
| **Rating System** | Simple +/-10 ELO | Implement proper Glicko-2 rating |
| **Move Validation** | Client-side trust | Add server-side move verification |
| **Error Recovery** | Basic handling | More granular error states |

### Medium Priority

| Area | Current State | Improvement |
|------|---------------|-------------|
| **Analysis Speed** | Sequential evaluation | Parallel analysis for faster results |
| **Board Themes** | Single brown theme | Multiple board/piece themes |
| **Sound Options** | All or nothing | Volume control, individual toggles |
| **Time Increments** | No increment | Add Fischer increment support |

### Low Priority

| Area | Current State | Improvement |
|------|---------------|-------------|
| **Animations** | Basic transitions | Piece movement animations |
| **Accessibility** | Limited | Screen reader support, color options |
| **Localization** | English only | Multi-language support |

---

## Future Roadmap

### Phase 1: Core Enhancements

#### 1.1 Puzzles & Training
- Daily puzzle challenges
- Tactics trainer with themes (forks, pins, skewers)
- Endgame practice positions
- Opening explorer

#### 1.2 Enhanced AI
- Opening book integration (ECO codes)
- Endgame tablebases (Syzygy)
- Personality modes (aggressive, defensive, positional)
- Hint system during games

#### 1.3 Social Features
- Friend list management
- Online status visibility
- Challenge friends directly
- In-game chat (with filters)

---

### Phase 2: Competitive Features

#### 2.1 Tournaments
- Create/join tournaments
- Swiss and round-robin formats
- Tournament brackets
- Prize/achievement system

#### 2.2 Leaderboards
- Global rating leaderboard
- Weekly/monthly rankings
- Country-based rankings
- Friends leaderboard

#### 2.3 Achievements & Rewards
- Milestone badges (games played, wins)
- Special achievements (brilliant moves, comebacks)
- Daily/weekly challenges
- Experience points system

---

### Phase 3: Advanced Features

#### 3.1 Game Review Tools
- Interactive analysis board
- Move alternatives exploration
- Opening classification
- Export to PGN format
- Share analysis with others

#### 3.2 Learning Center
- Video lessons integration
- Interactive tutorials
- Opening repertoire builder
- Weakness identification

#### 3.3 Spectator Mode
- Watch live games
- Featured games showcase
- Commentary system
- Tournament streaming

---

### Phase 4: Platform Expansion

#### 4.1 Web Application
- Browser-based version
- Cross-platform play
- Progressive Web App (PWA)

#### 4.2 Desktop Applications
- Windows native app
- macOS native app
- Linux support

#### 4.3 Smart Watch
- Move notifications
- Quick game preview
- Time alerts

---

### Phase 5: Premium Features

#### 5.1 Advanced Analysis
- Unlimited game analysis
- Deeper engine evaluation
- Cloud analysis storage
- Compare with master games

#### 5.2 Coaching Tools
- Schedule lessons with coaches
- Annotated game review
- Personalized study plans
- Progress tracking

#### 5.3 Custom Content
- Custom board themes
- Custom piece sets
- Profile customization
- Ad-free experience

---

## Technical Stack (Detailed)

### Mobile Application

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x |
| Language | Dart |
| State Management | Provider |
| Local Storage | SharedPreferences |
| Chess Logic | chess.dart package |
| Chess Board | flutter_chess_board |
| Audio | audioplayers |
| HTTP Client | http package |
| WebSocket | web_socket_channel |

### Backend Server

| Component | Technology |
|-----------|------------|
| Runtime | Bun |
| Language | TypeScript |
| WebSocket | Native Bun WebSocket |
| Chess Engine | Stockfish (via stockfish.js) |
| Database | MongoDB |
| ODM | Mongoose |
| Authentication | JWT (jsonwebtoken) |
| Password Hashing | bcryptjs |

### Database Schema

**Users Collection:**
```javascript
{
  username: String (unique),
  email: String (unique),
  passwordHash: String,
  rating: Number (default: 1200),
  ratingDeviation: Number,
  peakRating: Number,
  ratingHistory: [{ r: Number, d: Date }],
  stats: {
    games: Number,
    wins: Number,
    losses: Number,
    draws: Number,
    currentStreak: Number,
    bestStreak: Number
  },
  preferences: {
    boardTheme: String,
    pieceSet: String,
    soundEnabled: Boolean,
    autoQueen: Boolean,
    showLegalMoves: Boolean
  },
  lastActive: Date,
  isOnline: Boolean,
  createdAt: Date
}
```

**Games Collection:**
```javascript
{
  gameId: String (unique),
  players: { w: String, b: String },
  userIds: { w: ObjectId, b: ObjectId },
  fen: String,
  pgn: String,
  moves: [String], // UCI format: "e2e4"
  timeControl: { initial: Number, increment: Number },
  timeRemaining: { w: Number, b: Number },
  result: { winner: String, reason: String },
  analysis: {
    evaluated: Boolean,
    accuracy: { w: Number, b: Number },
    keyMoments: [{
      moveIndex: Number,
      evaluation: Number,
      bestMove: String,
      classification: String
    }]
  },
  isBot: Boolean,
  botDifficulty: Number,
  isPrivate: Boolean,
  status: String,
  startedAt: Date,
  endedAt: Date
}
```

---

## API Reference

### Authentication Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Create new account |
| POST | `/auth/login` | Login and get token |
| GET | `/auth/me` | Get current user info |

### Game Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/games/:id/analyze` | Analyze a completed game |

### WebSocket Events

**Client → Server:**
| Event | Description |
|-------|-------------|
| `CREATE_GAME` | Create a new game |
| `JOIN_GAME` | Join existing game |
| `QUEUE_MATCH` | Join matchmaking queue |
| `CANCEL_QUEUE` | Leave matchmaking queue |
| `MOVE` | Make a move |
| `RESIGN` | Resign the game |
| `OFFER_DRAW` | Offer a draw |
| `ACCEPT_DRAW` | Accept draw offer |
| `DECLINE_DRAW` | Decline draw offer |

**Server → Client:**
| Event | Description |
|-------|-------------|
| `GAME_CREATED` | Game created successfully |
| `GAME_JOINED` | Joined a game |
| `QUEUED` | Added to matchmaking |
| `MATCH_FOUND` | Match found, game starting |
| `QUEUE_TIMEOUT` | No match found |
| `MOVE_MADE` | Move was made |
| `GAME_OVER` | Game ended |
| `DRAW_OFFERED` | Opponent offered draw |
| `DRAW_DECLINED` | Draw was declined |
| `OPPONENT_DISCONNECTED` | Opponent lost connection |
| `OPPONENT_RECONNECTED` | Opponent reconnected |
| `ERROR` | Error occurred |

---

## Getting Started

### Prerequisites

- Flutter SDK 3.x
- Bun runtime
- MongoDB instance
- Node.js (for some tooling)

### Running the Backend

```bash
cd chess-backend
bun install
bun run dev
```

### Running the Mobile App

```bash
cd real_chess_mobile
flutter pub get
flutter run
```

### Configuration

Update `lib/utils/config.dart` with your server IP for physical device testing.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is proprietary software. All rights reserved.

---

*Document Version: 1.0*
*Last Updated: January 2025*
