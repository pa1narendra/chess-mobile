import { Elysia, t } from 'elysia';
import { GameManager } from './GameManager';
import { WebSocketMessage } from './types';
import connectDB from './db';
import { User } from './schemas/user';
import jwt from 'jsonwebtoken';

import { cors } from '@elysiajs/cors';

import { auth } from './auth';
import { searchRoutes } from './routes/searchRoutes';

connectDB();

const app = new Elysia()
    .use(cors())
    .use(auth)
    .get('/', () => 'Chess Backend Running')
    .use(searchRoutes);
const gameManager = new GameManager(
    (gameId, result) => {
        console.log(`[Main] GAME_OVER callback for ${gameId}, winner: ${result.winner}, reason: ${result.reason}`);
        const payload = JSON.stringify({
            type: 'GAME_OVER',
            winner: result.winner,
            reason: result.reason,
            fen: result.fen
        });
        if (app.server) {
            const success = app.server.publish(gameId, payload);
            console.log(`[Main] Published GAME_OVER to ${gameId}: ${success}`);
        } else {
            console.error('[Main] app.server is not ready, cannot publish GAME_OVER');
        }
    },
    (gameId, result) => {
        // onMove callback
        if (result.success && result.fen) {
            console.log(`[Main] onMove callback for ${gameId}`);
            const payload = JSON.stringify({
                type: 'UPDATE_BOARD',
                fen: result.fen,
                lastMove: result.lastMove,
                timeRemaining: gameManager.getGame(gameId)?.timeRemaining,
                history: result.history || []
            });
            if (app.server) {
                app.server.publish(gameId, payload);
            }

            // Failsafe: If game is over, ensure we send GAME_OVER message
            if (result.gameOver) {
                console.log(`[Main] onMove detected GAME_OVER for ${gameId}`);
                const gameOverPayload = JSON.stringify({
                    type: 'GAME_OVER',
                    winner: result.winner,
                    reason: result.reason,
                    fen: result.fen
                });
                if (app.server) {
                    app.server.publish(gameId, gameOverPayload);
                }
            }
        }
    }
);
const users = new Map<string, string>(); // ws.id -> playerId
const authenticatedUsers = new Map<string, string>(); // ws.id -> userId (MongoDB _id)

app.ws('/ws', {
    body: t.Any(), // Validate incoming messages if needed
    query: t.Object({
        token: t.Optional(t.String())
    }),
    open(ws) {
        console.log('Client connected:', ws.id);
        ws.subscribe('lobby');

        // Handle authentication via query param
        const token = ws.data.query.token;
        let authenticated = false;
        if (token) {
            try {
                const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key') as any;
                authenticatedUsers.set(ws.id, decoded.id);
                authenticated = true;
                console.log(`[WS] Authenticated connection: ${decoded.username} (${decoded.id})`);
            } catch (e) {
                console.log('[WS] Invalid token in query params');
            }
        }

        // Send connection acknowledgment so client knows it's connected
        ws.send(JSON.stringify({
            type: 'CONNECTED',
            authenticated,
            message: 'Connected to chess server'
        }));
    },
    async message(ws, message: any) {
        const msg = message as WebSocketMessage;


        if (msg.type === 'INIT_GAME') {
            let playerId = msg.playerId;
            let userId = authenticatedUsers.get(ws.id);

            // Fallback to token in message if not authenticated via query (backward compatibility)
            if (!userId && msg.token) {
                try {
                    const decoded = jwt.verify(msg.token, process.env.JWT_SECRET || 'your-secret-key') as any;
                    playerId = decoded.id;
                    userId = decoded.id;
                    if (userId) {
                        authenticatedUsers.set(ws.id, userId); // Cache it
                    }
                    console.log(`[WS] Authenticated user via msg: ${decoded.username} (${playerId})`);
                } catch (e) {
                    console.log('[WS] Invalid token in msg, falling back to guest ID');
                }
            } else if (userId) {
                // If authenticated, ensure playerId matches userId for consistency
                playerId = userId;
            }

            users.set(ws.id, playerId);

            const gameId = gameManager.createGame(playerId, msg.timeControl, false, msg.isPrivate, msg.isBot, msg.botDifficulty, userId);
            ws.subscribe(gameId);
            // Fetch usernames
            let whiteName = 'Player';
            let blackName = 'Opponent';

            if (userId) {
                // The creator is White in non-random games, or we check color
                const game = gameManager.getGame(gameId);
                const user = await User.findById(userId);
                if (user) {
                    if (game?.players.w === playerId) whiteName = user.username;
                    else if (game?.players.b === playerId) blackName = user.username;
                }
            }

            ws.send({
                type: 'GAME_CREATED',
                gameId,
                color: 'w',
                fen: gameManager.getGame(gameId)?.fen,
                timeRemaining: gameManager.getGame(gameId)?.timeRemaining,
                history: gameManager.getGame(gameId)?.history || [],
                whitePlayerName: whiteName,
                blackPlayerName: blackName
            });

            // Broadcast update to lobby
            app.server?.publish('lobby', JSON.stringify({
                type: 'PENDING_GAMES_UPDATE',
                games: gameManager.getPendingGames()
            }));
        } else if (msg.type === 'JOIN_GAME') {
            let playerId = msg.playerId;
            let userId = authenticatedUsers.get(ws.id);

            // Fallback to token in message
            if (!userId && msg.token) {
                try {
                    const decoded = jwt.verify(msg.token, process.env.JWT_SECRET || 'your-secret-key') as any;
                    playerId = decoded.id;
                    userId = decoded.id;
                    if (userId) {
                        authenticatedUsers.set(ws.id, userId);
                    }
                    console.log(`[WS] Authenticated user via msg: ${decoded.username} (${playerId})`);
                } catch (e) {
                    console.log('[WS] Invalid token in msg, falling back to guest ID');
                }
            } else if (userId) {
                playerId = userId;
            }

            users.set(ws.id, playerId);

            const color = gameManager.joinGame(msg.gameId, playerId, userId);
            if (color) {
                ws.subscribe(msg.gameId);
                // Fetch usernames
                let whiteName = 'White';
                let blackName = 'Black';

                const game = gameManager.getGame(msg.gameId);
                if (game) {
                    if (game.userIds.w) {
                        const u = await User.findById(game.userIds.w);
                        if (u) whiteName = u.username;
                    }
                    if (game.userIds.b) {
                        const u = await User.findById(game.userIds.b);
                        if (u) blackName = u.username;
                    }
                }

                ws.send({
                    type: 'GAME_JOINED',
                    gameId: msg.gameId,
                    color,
                    fen: gameManager.getGame(msg.gameId)?.fen,
                    timeRemaining: gameManager.getGame(msg.gameId)?.timeRemaining,
                    history: gameManager.getGame(msg.gameId)?.history || [],
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName
                });

                // Notify opponent that player joined
                ws.publish(msg.gameId, JSON.stringify({
                    type: 'OPPONENT_JOINED',
                    opponentId: playerId,
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName
                }));

                // Broadcast update to lobby
                app.server?.publish('lobby', JSON.stringify({
                    type: 'PENDING_GAMES_UPDATE',
                    games: gameManager.getPendingGames()
                }));
            } else {
                ws.send({ type: 'ERROR', message: 'Game full or invalid' });
            }
        } else if (msg.type === 'MOVE') {
            console.log(`[WS] Received MOVE: ${JSON.stringify(msg)}`);
            const playerId = users.get(ws.id);
            if (!playerId) {
                return;
            }

            const result = gameManager.makeMove(msg.gameId, playerId, { from: msg.from, to: msg.to, promotion: msg.promotion });

            if (result.success && result.fen) {
                console.log(`[WS] Move accepted. Broadcasting to ${msg.gameId}`);
                const payload = JSON.stringify({
                    type: 'UPDATE_BOARD',
                    fen: result.fen,
                    lastMove: { from: msg.from, to: msg.to },
                    timeRemaining: gameManager.getGame(msg.gameId)?.timeRemaining,
                    history: result.history || []
                });
                console.log(`[WS] Payload: ${payload}`);
                // Broadcast to others in game room
                ws.publish(msg.gameId, payload);
                // Also send to self so UI updates immediately
                ws.send(payload);

                if (result.gameOver) {
                    const gameOverPayload = JSON.stringify({
                        type: 'GAME_OVER',
                        winner: result.winner,
                        reason: result.reason,
                        fen: result.fen
                    });
                    ws.publish(msg.gameId, gameOverPayload);
                    ws.send(gameOverPayload);
                }
            } else {
                console.log(`[WS] Move rejected: ${result.error}`);
                ws.send({ type: 'ERROR', message: result.error || 'Invalid move' });
            }
        } else if (msg.type === 'RESIGN') {
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.resign(msg.gameId, playerId);
            }
        } else if (msg.type === 'DRAW_OFFER') {
            const playerId = users.get(ws.id);
            if (playerId) {
                const color = gameManager.offerDraw(msg.gameId, playerId);
                if (color) {
                    ws.publish(msg.gameId, JSON.stringify({ type: 'DRAW_OFFER', color }));
                }
            }
        } else if (msg.type === 'DRAW_ACCEPT') {
            const playerId = users.get(ws.id);
            if (playerId) {
                const success = gameManager.acceptDraw(msg.gameId, playerId);
                // If success, GAME_OVER handled by GameManager callback
            }
        } else if (msg.type === 'DRAW_DECLINE') {
            const playerId = users.get(ws.id);
            if (playerId) {
                const success = gameManager.declineDraw(msg.gameId, playerId);
                if (success) {
                    ws.publish(msg.gameId, JSON.stringify({ type: 'DRAW_DECLINE' }));
                }
            }
        } else if (msg.type === 'GET_PENDING_GAMES') {
            ws.send({
                type: 'PENDING_GAMES_UPDATE',
                games: gameManager.getPendingGames()
            });
        } else if (msg.type === 'QUICK_PLAY') {
            let playerId = msg.playerId;
            let userId = authenticatedUsers.get(ws.id);

            if (!userId && msg.token) {
                try {
                    const decoded = jwt.verify(msg.token, process.env.JWT_SECRET || 'your-secret-key') as any;
                    playerId = decoded.id;
                    userId = decoded.id;
                    if (userId) {
                        authenticatedUsers.set(ws.id, userId);
                    }
                } catch (e) {
                    console.log('[WS] Invalid token for quick play');
                }
            } else if (userId) {
                playerId = userId;
            }

            users.set(ws.id, playerId);


            const existingGameId = gameManager.findOpenGame(msg.timeControl);
            if (existingGameId) {
                // Join existing game
                const color = gameManager.joinGame(existingGameId, playerId, userId);
                if (color) {
                    ws.subscribe(existingGameId);
                    ws.send({
                        type: 'GAME_JOINED',
                        gameId: existingGameId,
                        color,
                        fen: gameManager.getGame(existingGameId)?.fen,
                        timeRemaining: gameManager.getGame(existingGameId)?.timeRemaining,
                        history: gameManager.getGame(existingGameId)?.history || []
                    });
                    ws.publish(existingGameId, JSON.stringify({
                        type: 'OPPONENT_JOINED',
                    }));

                    // Broadcast update to lobby
                    app.server?.publish('lobby', JSON.stringify({
                        type: 'PENDING_GAMES_UPDATE',
                        games: gameManager.getPendingGames()
                    }));
                }
            } else {
                // Create new game
                const gameId = gameManager.createGame(playerId, msg.timeControl, true, false, false, 1, userId);
                const game = gameManager.getGame(gameId);
                const color = game?.players.w === playerId ? 'w' : 'b';

                ws.subscribe(gameId);
                ws.send({
                    type: 'GAME_CREATED',
                    gameId,
                    color,
                    fen: game?.fen,
                    timeRemaining: game?.timeRemaining,
                    history: game?.history || []
                });

                // Broadcast update to lobby
                app.server?.publish('lobby', JSON.stringify({
                    type: 'PENDING_GAMES_UPDATE',
                    games: gameManager.getPendingGames()
                }));
            }
        } else if (msg.type === 'SYNC_TIME') {
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.checkTimeout(msg.gameId);
            }
        }
    },
    close(ws) {
        console.log('Client disconnected:', ws.id);
        const playerId = users.get(ws.id);
        users.delete(ws.id);
        authenticatedUsers.delete(ws.id);

        if (playerId) {
            // If the player was in a pending game (waiting for opponent), remove it
            const cleaned = gameManager.cleanupPendingGame(playerId);
            if (cleaned) {
                console.log(`[WS] Cleaned up pending game for ${playerId}`);
                // Broadcast update to lobby since a game was removed
                app.server?.publish('lobby', JSON.stringify({
                    type: 'PENDING_GAMES_UPDATE',
                    games: gameManager.getPendingGames()
                }));
            }
        }
    }
})
    // Game Analysis API endpoints
    .post('/api/games/:gameId/analyze', async ({ params, set }) => {
        const { gameId } = params;

        try {
            const { Game } = await import('./schemas/game');
            const { Chess } = await import('chess.js');

            // Fetch game from database
            const game = await Game.findOne({ gameId });

            if (!game) {
                set.status = 404;
                return { error: 'Game not found' };
            }

            // Check if already analyzed
            if (game.analysis?.evaluated) {
                return {
                    message: 'Game already analyzed',
                    analysis: game.analysis
                };
            }

            // Reconstruct game positions from moves
            const chess = new Chess();
            const positions: Array<{ moveIndex: number; fen: string; san: string; color: string }> = [];

            // Initial position
            positions.push({ moveIndex: 0, fen: chess.fen(), san: '', color: 'w' });

            // Play through all moves
            for (let i = 0; i < game.moves.length; i++) {
                const move = game.moves[i];
                // Skip moves with missing required data
                if (!move.from || !move.to || !move.san || !move.color) continue;

                chess.move({ from: move.from, to: move.to, promotion: move.promotion || undefined });
                positions.push({
                    moveIndex: i + 1,
                    fen: chess.fen(),
                    san: move.san,
                    color: move.color
                });
            }

            // Analyze each position using Stockfish
            const evaluations = [];
            let previousEval = 0;

            for (let i = 0; i < positions.length; i++) {
                const pos = positions[i];
                const { evaluation, bestMove } = await gameManager.botManager.getPositionEvaluation(pos.fen);

                // Classify move (skip initial position)
                let classification = null;
                if (i > 0) {
                    // Flip evaluation if black's move (Stockfish always returns from white's perspective)
                    const currentEval = pos.color === 'b' ? -evaluation : evaluation;
                    const prevEval = positions[i - 1].color === 'b' ? -previousEval : previousEval;

                    const evalDrop = prevEval - currentEval; // Positive means position got worse

                    if (evalDrop > 300) {
                        classification = 'blunder';
                    } else if (evalDrop > 150) {
                        classification = 'mistake';
                    } else if (evalDrop > 50) {
                        classification = 'inaccuracy';
                    } else if (evalDrop < -100) {
                        classification = 'brilliant';
                    } else if (evalDrop < -50) {
                        classification = 'great';
                    } else if (evalDrop < -10) {
                        classification = 'good';
                    } else {
                        classification = 'book';
                    }
                }

                evaluations.push({
                    moveIndex: pos.moveIndex,
                    fen: pos.fen,
                    evaluation,
                    bestMove,
                    classification
                });

                previousEval = evaluation;
            }

            // Store analysis in database
            game.analysis = {
                evaluated: true,
                evaluations: evaluations as any, // Type assertion to handle Mongoose DocumentArray
                analyzedAt: new Date()
            };

            await game.save();

            return {
                message: 'Analysis complete',
                analysis: game.analysis
            };

        } catch (error: any) {
            console.error('[Analysis] Error:', error);
            set.status = 500;
            return { error: error.message || 'Analysis failed' };
        }
    })
    .get('/api/games/:gameId/analysis', async ({ params, set }) => {
        const { gameId } = params;

        try {
            const { Game } = await import('./schemas/game');

            const game = await Game.findOne({ gameId });

            if (!game) {
                set.status = 404;
                return { error: 'Game not found' };
            }

            if (!game.analysis?.evaluated) {
                set.status = 404;
                return { error: 'Game has not been analyzed yet' };
            }

            return {
                analysis: game.analysis,
                moves: game.moves
            };

        } catch (error: any) {
            console.error('[Analysis] Error:', error);
            set.status = 500;
            return { error: error.message || 'Failed to fetch analysis' };
        }
    })
    .listen({ port: 8080, hostname: '0.0.0.0' });

console.log(`🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`);
console.log('SERVER VERSION: WS-PUBLISH-FIX-V1');


