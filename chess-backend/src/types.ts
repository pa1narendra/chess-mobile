export type PlayerColor = 'w' | 'b';

export interface GameState {
    id: string;
    fen: string;
    players: {
        w?: string; // Player ID
        b?: string; // Player ID
    };
    userIds: {
        w?: string; // MongoDB User ID (for registered users)
        b?: string; // MongoDB User ID (for registered users)
    };
    history: string[];
    turn: PlayerColor;
    timeRemaining: {
        w: number; // milliseconds
        b: number; // milliseconds
    };
    lastMoveTime: number; // timestamp
    isPrivate?: boolean;
    isBot?: boolean;
    botDifficulty?: number;
    status: 'active' | 'finished' | 'waiting';
    drawOffer?: 'w' | 'b'; // Color of player who offered draw
    finishedAt?: number;
    result?: {
        winner: string | null;
        reason: string | null;
    };
}

export type WebSocketMessage =
    | { type: 'INIT_GAME'; timeControl: number; playerId: string; token?: string; isPrivate?: boolean; isBot?: boolean; botDifficulty?: number }
    | { type: 'JOIN_GAME'; gameId: string; playerId: string; token?: string }
    | { type: 'MOVE'; from: string; to: string; promotion?: string; token?: string; gameId: string }
    | { type: 'RESIGN'; gameId: string; playerId: string }
    | { type: 'DRAW_OFFER'; gameId: string; token?: string }
    | { type: 'DRAW_ACCEPT'; gameId: string; token?: string }
    | { type: 'DRAW_DECLINE'; gameId: string; token?: string }
    | { type: 'GET_PENDING_GAMES'; token?: string }
    | { type: 'QUICK_PLAY'; timeControl: number; playerId: string; isBot?: boolean; botDifficulty?: number; token?: string }
    | { type: 'CANCEL_QUEUE'; token?: string }
    | { type: 'SYNC_TIME'; gameId: string; token?: string }
    | { type: 'REJOIN_GAME'; token?: string }
    | { type: 'SUBSCRIBE_GAME'; gameId: string };

export type WebSocketResponse =
    | { type: 'GAME_CREATED'; gameId: string; color: PlayerColor; fen: string; timeRemaining: { w: number; b: number }; history: string[] }
    | { type: 'GAME_JOINED'; gameId: string; color: PlayerColor; fen: string; timeRemaining: { w: number; b: number }; history: string[] }
    | { type: 'UPDATE_BOARD'; fen: string; lastMove?: { from: string; to: string }; timeRemaining: { w: number; b: number }; history: string[] }
    | { type: 'GAME_OVER'; winner: string | null; reason: string | null; fen?: string }
    | { type: 'ERROR'; message: string }
    | { type: 'OPPONENT_DISCONNECTED' }
    | { type: 'PENDING_GAMES_UPDATE'; games: { id: string; players: { w?: string; b?: string }; timeControl: number }[] };
