import { Chess } from 'chess.js';
import { GameState, PlayerColor } from './types';
import { Game } from './schemas/game';
import { User } from './schemas/user';
import { BotManager } from './BotManager';

export class GameManager {
    private games: Map<string, GameState> = new Map();
    private chessInstances: Map<string, Chess> = new Map();
    private timeoutHandlers: Map<string, ReturnType<typeof setTimeout>> = new Map();
    private onMove?: (gameId: string, result: any) => void;
    private onGameOver: (gameId: string, result: any) => void;
    public botManager: BotManager;

    constructor(onGameOver: (gameId: string, result: any) => void, onMove?: (gameId: string, result: any) => void) {
        this.onGameOver = onGameOver;
        this.onMove = onMove;
        this.botManager = new BotManager();
    }

    createGame(playerId: string, durationMinutes: number = 10, randomizeColor: boolean = false, isPrivate: boolean = false, isBot: boolean = false, botDifficulty: number = 1, userId?: string): string {
        const gameId = Math.random().toString(36).substring(2, 8);
        const chess = new Chess();
        const durationMs = durationMinutes * 60 * 1000;

        let players: { w?: string; b?: string } = { w: playerId };
        let playerColor: PlayerColor = 'w';

        if (isBot) {
            // If bot, player is always white for now (or random if requested)
            if (randomizeColor && Math.random() < 0.5) {
                players = { b: playerId, w: 'bot' };
                playerColor = 'b';
            } else {
                players = { w: playerId, b: 'bot' };
                playerColor = 'w';
            }
        } else if (randomizeColor && Math.random() < 0.5) {
            players = { b: playerId };
            playerColor = 'b';
        }

        // Build userIds for in-memory state
        const memoryUserIds: { w?: string; b?: string } = {};
        if (userId && /^[0-9a-fA-F]{24}$/.test(userId)) {
            if (players.w === playerId) {
                memoryUserIds.w = userId;
            } else if (players.b === playerId) {
                memoryUserIds.b = userId;
            }
        }

        this.games.set(gameId, {
            id: gameId,
            fen: chess.fen(),
            players,
            userIds: memoryUserIds,
            history: [],
            turn: 'w',
            timeRemaining: { w: durationMs, b: durationMs },
            lastMoveTime: Date.now(),
            isPrivate,
            isBot,
            botDifficulty,
            status: 'active'
        });

        this.chessInstances.set(gameId, chess);

        // Save to DB
        const userIds: { w?: string; b?: string } = {};

        console.log(`[GameManager] createGame: gameId=${gameId}, playerId=${playerId}, userId=${userId}`);
        console.log(`[GameManager] players:`, players);

        // Creator is always white, so if userId is provided, set it
        if (userId && /^[0-9a-fA-F]{24}$/.test(userId)) {
            // If player is white, set userIds.w
            if (players.w === playerId) {
                userIds.w = userId;
            } else if (players.b === playerId) {
                userIds.b = userId;
            }
        }
        console.log(`[GameManager] computed userIds:`, userIds);

        const gameDB = new Game({
            gameId,
            players,
            userIds,
            fen: chess.fen(),
            moves: [],
            timeControl: {
                initial: durationMs,
                increment: 0
            },
            timeRemaining: {
                w: durationMs,
                b: durationMs
            },
            isBot,
            botDifficulty,
            isPrivate,
            status: isBot ? 'active' : 'waiting', // Bot games start immediately
            startedAt: isBot ? new Date() : undefined
        });
        gameDB.save()
            .then(() => console.log(`[DB] Game ${gameId} created with userIds:`, userIds))
            .catch(err => console.error(`[DB] Failed to save game ${gameId}:`, err.message));

        // If bot is white, make first move
        if (isBot && players.w === 'bot') {
            this.triggerBotMove(gameId);
        }

        return gameId;
    }

    joinGame(gameId: string, playerId: string, userId?: string): PlayerColor | null {
        const game = this.games.get(gameId);
        if (!game) return null;

        // Allow re-joining finished games to see result
        if (game.status === 'finished') {
            if (game.players.w === playerId) return 'w';
            if (game.players.b === playerId) return 'b';
            return null; // Spectators not yet supported fully for finished games in this logic
        }

        if (game.players.w === playerId) return 'w';
        if (game.players.b === playerId) return 'b';

        if (!game.players.w) {
            game.players.w = playerId;
            // Update DB - game is now starting
            const updateData: any = {
                'players.w': playerId,
                status: 'active',
                startedAt: new Date(),
                updatedAt: new Date()
            };
            if (userId && /^[0-9a-fA-F]{24}$/.test(userId)) {
                updateData['userIds.w'] = userId;
                game.userIds.w = userId; // Also update in-memory
            }
            Game.findOneAndUpdate({ gameId }, updateData).exec();

            // Start timer (White moves first)
            game.lastMoveTime = Date.now();
            this.resetMoveTimer(gameId);

            return 'w';
        }
        if (!game.players.b) {
            game.players.b = playerId;
            // Update DB - game is now starting
            const updateData: any = {
                'players.b': playerId,
                status: 'active',
                startedAt: new Date(),
                updatedAt: new Date()
            };
            if (userId && /^[0-9a-fA-F]{24}$/.test(userId)) {
                updateData['userIds.b'] = userId;
                game.userIds.b = userId; // Also update in-memory
            }
            Game.findOneAndUpdate({ gameId }, updateData).exec();

            // Start timer (White moves first)
            game.lastMoveTime = Date.now();
            this.resetMoveTimer(gameId);

            return 'b';
        }

        return null; // Game full
    }

    makeMove(gameId: string, playerId: string, move: { from: string; to: string; promotion?: string }): { success: boolean, fen?: string, history?: string[], error?: string, gameOver?: boolean, winner?: string | null, reason?: string | null, lastMove?: { from: string, to: string } } {
        const game = this.games.get(gameId);
        const chess = this.chessInstances.get(gameId);

        console.log(`[GameManager] makeMove: gameId=${gameId}, playerId=${playerId}, move=${JSON.stringify(move)}`);

        if (!game || !chess) {
            console.log('[GameManager] Game or Chess instance not found');
            return { success: false, error: 'Game not found' };
        }

        const playerColor = game.players.w === playerId ? 'w' : (game.players.b === playerId ? 'b' : null);
        console.log(`[GameManager] Turn: ${game.turn}, PlayerColor: ${playerColor}`);

        if (!playerColor) {
            console.log('[GameManager] Player not in game');
            return { success: false, error: 'Player not in game' };
        }

        if (game.turn !== playerColor) {
            console.log('[GameManager] Not player turn');
            return { success: false, error: 'Not your turn' };
        }

        // Check if player has time remaining
        console.log(`[GameManager] Time remaining: ${game.timeRemaining[playerColor]}`);
        if (game.timeRemaining[playerColor] <= 0) {
            console.log('[GameManager] Time out');
            return { success: false, error: 'Time out' };
        }

        try {
            const result = chess.move(move); // Validates and makes the move
            if (result) {
                const now = Date.now();
                const elapsed = now - game.lastMoveTime;
                game.timeRemaining[game.turn] -= elapsed;
                console.log(`[GameManager] Move valid. Elapsed: ${elapsed}, New Time: ${game.timeRemaining[game.turn]}`);

                if (game.timeRemaining[game.turn] < 0) {
                    game.timeRemaining[game.turn] = 0;
                }

                game.lastMoveTime = now;
                game.fen = chess.fen();
                game.history.push(result.san);
                game.turn = chess.turn();

                // Update DB
                Game.findOneAndUpdate(
                    { gameId },
                    {
                        $push: {
                            moves: {
                                from: move.from,
                                to: move.to,
                                promotion: move.promotion,
                                san: result.san,
                                color: result.color,
                                timestamp: new Date()
                            }
                        },
                        fen: game.fen,
                        pgn: chess.pgn(),
                        timeRemaining: {
                            w: game.timeRemaining.w,
                            b: game.timeRemaining.b
                        },
                        updatedAt: new Date()
                    }
                ).exec().catch(err => console.error(`[GameManager] Failed to save move to DB:`, err));

                let gameOver = false;
                let winner: string | null = null;
                let reason: string | null = null;

                if (chess.isGameOver()) {
                    console.log(`[GameManager] Game Over detected for ${gameId}`);
                    gameOver = true;
                    if (chess.isCheckmate()) {
                        reason = 'checkmate';
                        winner = chess.turn() === 'w' ? 'b' : 'w';
                    } else if (chess.isDraw()) {
                        reason = 'draw';
                        winner = 'draw';
                    } else if (chess.isStalemate()) {
                        reason = 'stalemate';
                        winner = 'draw';
                    } else if (chess.isInsufficientMaterial()) {
                        reason = 'insufficient material';
                        winner = 'draw';
                    } else if (chess.isThreefoldRepetition()) {
                        reason = 'threefold repetition';
                        winner = 'draw';
                    }

                    // Update DB with result
                    Game.findOneAndUpdate(
                        { gameId },
                        {
                            result: { winner, reason }
                        }
                    ).exec();

                    // Update User Stats
                    // this.updateUserStats(game.players.w, game.players.b, winner);

                    // Clear timer if game over
                    // this.clearTimer(gameId);

                    // Call handleGameOver to clean up resources and notify
                    this.handleGameOver(gameId, winner, reason);
                } else {
                    // Reset timer for next player
                    this.resetMoveTimer(gameId);

                    // If it's bot's turn, trigger bot move
                    if (game.isBot && !gameOver) {
                        const nextTurn = game.turn;
                        const botColor = game.players.w === 'bot' ? 'w' : 'b';
                        if (nextTurn === botColor) {
                            this.triggerBotMove(gameId);
                        }
                    }
                }

                return { success: true, fen: game.fen, history: game.history, gameOver, winner, reason, lastMove: { from: move.from, to: move.to } };
            } else {
                console.log('[GameManager] Invalid move (chess.js returned null)');
                return { success: false, error: 'Invalid move' };
            }
        } catch (e) {
            console.log('[GameManager] Exception during move:', e);
            return { success: false, error: 'Invalid move exception' };
        }
    }

    private async triggerBotMove(gameId: string) {
        const game = this.games.get(gameId);
        if (!game || !game.isBot) return;

        // Small delay to simulate thinking and feel natural
        setTimeout(async () => {
            try {
                const bestMove = await this.botManager.getBestMove(game.fen, game.botDifficulty || 1);
                console.log(`[GameManager] Bot best move: ${bestMove}`);

                // Convert UCI move (e2e4) to from/to
                const from = bestMove.substring(0, 2);
                const to = bestMove.substring(2, 4);
                const promotion = bestMove.length > 4 ? bestMove.substring(4, 5) : undefined;

                // We need to call makeMove, but we need to bypass the playerId check or use 'bot' ID
                // Since makeMove checks playerId, we'll create a special internal method or just hack it here.
                // Let's refactor makeMove to allow internal calls or just duplicate logic slightly for safety.
                // Actually, let's just use 'bot' as playerId since we set it in createGame.

                const result = this.makeMove(gameId, 'bot', { from, to, promotion });

                if (result.success) {
                    // We need to broadcast this move!
                    // But makeMove doesn't broadcast, it returns result.
                    // The caller of makeMove usually broadcasts.
                    // Since we are calling it asynchronously here, we need a way to broadcast.
                    // We can pass a callback or emit an event.
                    // Or we can use the onGameOver callback to also handle moves? No, that's for game over.
                    // We need a new callback for onMove.

                    // Ideally GameManager should emit events.
                    // For now, let's assume we need to add an onMove callback to GameManager constructor.
                    if (this.onMove) {
                        this.onMove(gameId, result);
                    }
                }
            } catch (e) {
                console.error(`[GameManager] Bot failed to move:`, e);
            }
        }, 500 + Math.random() * 1000);
    }

    // We need to add onMove to constructor and class
    // ... (rest of the class)


    getGame(gameId: string): GameState | undefined {
        return this.games.get(gameId);
    }

    removePlayer(playerId: string) {
        for (const [gameId, game] of this.games.entries()) {
            if (game.players.w === playerId) {
                game.players.w = undefined;
                return gameId;
            }
            if (game.players.b === playerId) {
                game.players.b = undefined;
                return gameId;
            }
        }
        return null;
    }

    getOpponentId(gameId: string, playerId: string): string | undefined {
        const game = this.games.get(gameId);
        if (!game) return undefined;
        return game.players.w === playerId ? game.players.b : game.players.w;
    }

    getPendingGames() {
        return Array.from(this.games.values())
            .filter(game => game.status === 'active' && (!game.players.b || !game.players.w) && !game.isPrivate)
            .map(game => ({
                id: game.id,
                players: game.players,
                timeControl: game.timeRemaining.w / (60 * 1000) // Assuming initial time was symmetric
            }));
    }

    findOpenGame(timeControl: number): string | null {
        // Find a game with a missing player and matching time control (approx)
        const targetMs = timeControl * 60 * 1000;

        for (const game of this.games.values()) {
            if (game.status === 'active' && (!game.players.b || !game.players.w) && Math.abs(game.timeRemaining.w - targetMs) < 1000 && !game.isPrivate) {
                return game.id;
            }
        }
        return null;
    }

    cleanupPendingGame(playerId: string) {
        for (const [gameId, game] of this.games.entries()) {
            // Check if this player is in the game AND the game is pending (missing one player)
            const isPlayerInGame = game.players.w === playerId || game.players.b === playerId;
            const isPending = !game.players.w || !game.players.b;

            if (isPlayerInGame && isPending) {
                console.log(`[GameManager] Cleaning up pending game ${gameId} for disconnected player ${playerId}`);
                this.games.delete(gameId);
                this.clearTimer(gameId);
                this.chessInstances.delete(gameId);

                // Also remove from DB if needed, or mark as abandoned
                Game.deleteOne({ gameId }).exec();
                return true;
            }
        }
        return false;
    }

    private clearTimer(gameId: string) {
        const timer = this.timeoutHandlers.get(gameId);
        if (timer) {
            clearTimeout(timer);
            this.timeoutHandlers.delete(gameId);
        }
    }

    private resetMoveTimer(gameId: string) {
        this.clearTimer(gameId);
        const game = this.games.get(gameId);
        if (!game) return;

        const turn = game.turn;
        const timeRemaining = game.timeRemaining[turn];

        if (timeRemaining <= 0) {
            this.handleTimeout(gameId);
            return;
        }

        console.log(`[GameManager] Setting timeout for ${gameId} (${turn}) in ${timeRemaining}ms`);

        const timer = setTimeout(() => {
            this.handleTimeout(gameId);
        }, timeRemaining); // Use exact time remaining

        this.timeoutHandlers.set(gameId, timer);
    }

    resign(gameId: string, playerId: string) {
        const game = this.games.get(gameId);
        if (!game) return;

        const playerColor = game.players.w === playerId ? 'w' : (game.players.b === playerId ? 'b' : null);
        if (!playerColor) return;

        const winner = playerColor === 'w' ? 'b' : 'w';
        const reason = 'resignation';

        this.handleGameOver(gameId, winner, reason);
    }

    draw(gameId: string, playerId: string) {
        // For simplicity, we'll just allow immediate draw. 
        // In a real app, this should be a draw offer/accept flow.
        const game = this.games.get(gameId);
        if (!game) return;

        const playerColor = game.players.w === playerId ? 'w' : (game.players.b === playerId ? 'b' : null);
        if (!playerColor) return;

        const winner = 'draw';
        const reason = 'mutual agreement';

        this.handleGameOver(gameId, winner, reason);
    }

    private handleGameOver(gameId: string, winner: string | null, reason: string | null) {
        const game = this.games.get(gameId);
        if (!game) return;

        // Prevent double processing
        if (game.status === 'finished') {
            console.log(`[GameManager] Game ${gameId} already finished, skipping handleGameOver`);
            return;
        }

        // Update DB with complete final state
        const chess = this.chessInstances.get(gameId);
        Game.findOneAndUpdate(
            { gameId },
            {
                result: { winner, reason },
                fen: game.fen,
                pgn: chess?.pgn() || '',
                status: 'finished',
                timeRemaining: {
                    w: game.timeRemaining.w,
                    b: game.timeRemaining.b
                },
                endedAt: new Date(),
                updatedAt: new Date()
            }
        ).exec().catch(err => console.error(`[GameManager] Failed to save game result to DB:`, err));

        // Update User Stats (use userIds for registered users, not players which might be 'bot')
        this.updateUserStats(game.userIds.w, game.userIds.b, winner);

        // Mark as finished instead of deleting
        game.status = 'finished';
        game.finishedAt = Date.now();
        game.result = { winner, reason };

        this.clearTimer(gameId);
        // We can keep chess instance for a while or delete it. 
        // Keeping it allows move validation if we wanted to allow analysis, but for now we can delete it to save memory if needed.
        // But let's keep it for consistency until cleanup.

        // Schedule cleanup
        // User requested not to delete games after completion.
        // We will keep them in memory. In a production app, we would want some cleanup strategy (e.g. LRU or 24h).
        // setTimeout(() => {
        //     this.games.delete(gameId);
        //     this.chessInstances.delete(gameId);
        //     console.log(`[GameManager] Cleaned up finished game ${gameId}`);
        // }, 1000 * 60 * 60); // Keep for 1 hour
    }

    private async updateUserStats(whiteId: string | undefined, blackId: string | undefined, winner: string | null) {
        if (!whiteId || !blackId) return;

        const updateStats = async (playerId: string, result: 'win' | 'loss' | 'draw') => {
            try {
                // Check if valid ObjectId (24 hex chars)
                if (!/^[0-9a-fA-F]{24}$/.test(playerId)) return;

                const inc: any = { gamesPlayed: 1 };
                if (result === 'win') {
                    inc.wins = 1;
                    inc.rating = 10; // Simple ELO +10
                } else if (result === 'loss') {
                    inc.losses = 1;
                    inc.rating = -10; // Simple ELO -10
                } else {
                    inc.draws = 1;
                }

                await User.findByIdAndUpdate(playerId, { $inc: inc });
            } catch (e) {
                console.log(`[GameManager] Failed to update stats for ${playerId}:`, e);
            }
        };

        if (winner === 'draw') {
            await updateStats(whiteId, 'draw');
            await updateStats(blackId, 'draw');
        } else if (winner === 'w') {
            await updateStats(whiteId, 'win');
            await updateStats(blackId, 'loss');
        } else if (winner === 'b') {
            await updateStats(whiteId, 'loss');
            await updateStats(blackId, 'win');
        }
    }

    checkTimeout(gameId: string) {
        const game = this.games.get(gameId);
        if (!game) return;

        const now = Date.now();
        const elapsed = now - game.lastMoveTime;
        const timeRemaining = game.timeRemaining[game.turn] - elapsed;

        if (timeRemaining <= 0) {
            console.log(`[GameManager] checkTimeout: Time is up for ${gameId}, triggering timeout`);
            this.handleTimeout(gameId);
        } else {
            console.log(`[GameManager] checkTimeout: Time not up yet for ${gameId} (${timeRemaining}ms remaining)`);
        }
    }

    private handleTimeout(gameId: string) {
        console.log(`[GameManager] handleTimeout triggered for ${gameId}`);
        const game = this.games.get(gameId);
        if (!game) {
            console.log(`[GameManager] Game ${gameId} not found in handleTimeout`);
            return;
        }

        // Prevent race condition - don't process if game already finished
        if (game.status === 'finished') {
            console.log(`[GameManager] Game ${gameId} already finished, skipping timeout`);
            return;
        }

        // Double check time (optional, but good for safety)
        const now = Date.now();
        const elapsed = now - game.lastMoveTime;
        const timeRemaining = game.timeRemaining[game.turn] - elapsed;
        console.log(`[GameManager] Time remaining at timeout: ${timeRemaining}ms`);

        // If we are here via setTimeout, time should be roughly <= 0.

        const winner = game.turn === 'w' ? 'b' : 'w';
        const reason = 'timeout';
        if (this.onGameOver) {
            console.log(`[GameManager] Calling onGameOver for ${gameId}`);
            this.onGameOver(gameId, { winner, reason, fen: game.fen });
        } else {
            console.log(`[GameManager] onGameOver callback is missing!`);
        }

        // Clean up the game
        this.handleGameOver(gameId, winner, reason);
    }

    // private handleTimeout(gameId: string) {
    //     const game = this.games.get(gameId);
    //     if (!game) return;

    //     // Double check time (optional, but good for safety)
    //     const now = Date.now();
    //     const elapsed = now - game.lastMoveTime;
    //     const timeRemaining = game.timeRemaining[game.turn] - elapsed;

    //     // If we are here via setTimeout, time should be roughly <= 0.

    //     const winner = game.turn === 'w' ? 'b' : 'w';
    //     const reason = 'timeout';

    //     this.handleGameOver(gameId, winner, reason);
    // }
}
