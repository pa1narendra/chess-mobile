import { Elysia, t } from 'elysia';
import { GameManager } from './GameManager';
import connectDB from './db';
import { User } from './schemas/user';

import { cors } from '@elysiajs/cors';

import { auth } from './auth';
import { searchRoutes } from './routes/searchRoutes';
import { apiRoutes } from './routes/apiRoutes';
import { verifyToken } from './middleware/authMiddleware';

connectDB();

// --- Rate limiting state ---
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_WINDOW = 60_000; // 1 minute
const RATE_LIMIT_MAX_WS = 60; // max messages per minute per connection

function checkRateLimit(id: string): boolean {
    const now = Date.now();
    const entry = rateLimitMap.get(id);
    if (!entry || now > entry.resetAt) {
        rateLimitMap.set(id, { count: 1, resetAt: now + RATE_LIMIT_WINDOW });
        return true;
    }
    entry.count++;
    return entry.count <= RATE_LIMIT_MAX_WS;
}

// Cleanup rate limit entries every 5 minutes
setInterval(() => {
    const now = Date.now();
    for (const [id, entry] of rateLimitMap) {
        if (now > entry.resetAt) rateLimitMap.delete(id);
    }
}, 5 * 60 * 1000);

// --- Helper: resolve player identity from WS connection ---
// Returns { playerId, userId } where:
// - For authenticated users: both are the MongoDB _id
// - For guests: playerId is a server-generated guest ID, userId is undefined
function resolvePlayer(
    wsId: string,
    authenticatedUsers: Map<string, string>,
    guestIds: Map<string, string>,
    token?: string
): { playerId: string; userId: string | undefined } {
    // Check if already authenticated on this connection
    let userId = authenticatedUsers.get(wsId);
    if (userId) {
        return { playerId: userId, userId };
    }

    // Try to authenticate via token in message
    if (token) {
        const decoded = verifyToken(token);
        if (decoded) {
            authenticatedUsers.set(wsId, decoded.id);
            return { playerId: decoded.id, userId: decoded.id };
        }
    }

    // Guest: generate a stable server-side ID for this connection
    let guestId = guestIds.get(wsId);
    if (!guestId) {
        guestId = `guest_${wsId}_${Date.now()}`;
        guestIds.set(wsId, guestId);
    }
    return { playerId: guestId, userId: undefined };
}

// --- Helper: fetch player names for a game ---
async function fetchPlayerNames(game: any): Promise<{ whiteName: string; blackName: string }> {
    let whiteName = 'White';
    let blackName = 'Black';

    if (game?.userIds?.w) {
        const u = await User.findById(game.userIds.w).select('username profile.displayName');
        if (u) whiteName = (u as any).profile?.displayName || u.username;
    }
    if (game?.userIds?.b) {
        const u = await User.findById(game.userIds.b).select('username profile.displayName');
        if (u) blackName = (u as any).profile?.displayName || u.username;
    }

    // Handle bot games
    if (game?.isBot) {
        if (game.players?.w === 'bot') whiteName = 'Bot';
        if (game.players?.b === 'bot') blackName = 'Bot';
    }

    return { whiteName, blackName };
}

// --- Validate chess square format ---
function isValidSquare(s: any): boolean {
    return typeof s === 'string' && /^[a-h][1-8]$/.test(s);
}

function isValidPromotion(p: any): boolean {
    return p === undefined || (typeof p === 'string' && /^[qrbn]$/i.test(p));
}

function isValidGameId(id: any): boolean {
    return typeof id === 'string' && /^\d{6}$/.test(id);
}

const BLOCKED_WORDS = ['fuck', 'shit', 'bitch', 'damn', 'dick', 'bastard', 'cunt', 'slut', 'whore', 'nigger', 'faggot', 'retard'];
function containsProfanity(text: string): boolean {
    const lower = text.toLowerCase();
    return BLOCKED_WORDS.some(word => lower.includes(word));
}

// --- App setup ---
const app = new Elysia()
    .use(cors({
        origin: process.env.CORS_ORIGIN || true,
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    }))
    .use(auth)
    .get('/', () => 'Chess Backend Running')
    .get('/health', () => ({ status: 'ok', uptime: process.uptime() }))
    .use(searchRoutes)
    .use(apiRoutes);

const gameManager = new GameManager(
    (gameId, result) => {
        const payload = JSON.stringify({
            type: 'GAME_OVER',
            winner: result.winner,
            reason: result.reason,
            fen: result.fen,
            ratingChanges: result.ratingChanges
        });
        if (app.server) {
            app.server.publish(gameId, payload);
        }
    },
    (gameId, result) => {
        if (result.success && result.fen) {
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
            // Game-over is handled by the onGameOver callback — no duplication here
        }
    },
    (gameId, playerId, color) => {
        const payload = JSON.stringify({
            type: 'OPPONENT_DISCONNECTED',
            message: 'Opponent disconnected. They have 60 seconds to reconnect.',
            disconnectedColor: color
        });
        if (app.server) {
            app.server.publish(gameId, payload);
        }
    },
    (gameId, playerId) => {
        const payload = JSON.stringify({
            type: 'OPPONENT_RECONNECTED',
            message: 'Opponent has reconnected!'
        });
        if (app.server) {
            app.server.publish(gameId, payload);
        }
    }
);

const users = new Map<string, string>();              // ws.id -> playerId
const authenticatedUsers = new Map<string, string>(); // ws.id -> userId (MongoDB _id)
const guestIds = new Map<string, string>();            // ws.id -> server-generated guest ID

app.ws('/ws', {
    body: t.Any(),
    query: t.Object({
        token: t.Optional(t.String())
    }),
    open(ws) {
        console.log('Client connected:', ws.id);
        ws.subscribe('lobby');

        // Authenticate via query param token
        const token = ws.data.query.token;
        let authenticated = false;
        if (token) {
            const decoded = verifyToken(token);
            if (decoded) {
                authenticatedUsers.set(ws.id, decoded.id);
                authenticated = true;
                console.log(`[WS] Authenticated connection: ${decoded.username} (${decoded.id})`);
            }
        }

        ws.send(JSON.stringify({
            type: 'CONNECTED',
            authenticated,
            message: 'Connected to chess server'
        }));
    },
    async message(ws, message: any) {
        // Rate limit check
        if (!checkRateLimit(ws.id)) {
            ws.send(JSON.stringify({ type: 'ERROR', message: 'Rate limit exceeded. Slow down.' }));
            return;
        }

        const msg = message as any;
        if (!msg || !msg.type) {
            ws.send({ type: 'ERROR', message: 'Invalid message format' });
            return;
        }

        if (msg.type === 'INIT_GAME') {
            const { playerId, userId } = resolvePlayer(ws.id, authenticatedUsers, guestIds, msg.token);
            users.set(ws.id, playerId);

            const timeControl = typeof msg.timeControl === 'number' ? Math.min(Math.max(msg.timeControl, 1), 60) : 10;
            const botDifficulty = typeof msg.botDifficulty === 'number' ? Math.min(Math.max(msg.botDifficulty, 1), 5) : 1;

            const gameId = gameManager.createGame(playerId, timeControl, false, !!msg.isPrivate, !!msg.isBot, botDifficulty, userId);
            ws.subscribe(gameId);

            const game = gameManager.getGame(gameId);
            const { whiteName, blackName } = await fetchPlayerNames(game);

            ws.send({
                type: 'GAME_CREATED',
                gameId,
                color: 'w',
                fen: game?.fen,
                timeRemaining: game?.timeRemaining,
                history: game?.history || [],
                whitePlayerName: whiteName,
                blackPlayerName: blackName,
                isPrivate: !!msg.isPrivate
            });

            app.server?.publish('lobby', JSON.stringify({
                type: 'PENDING_GAMES_UPDATE',
                games: gameManager.getPendingGames()
            }));

        } else if (msg.type === 'JOIN_GAME') {
            if (!isValidGameId(msg.gameId)) {
                ws.send({ type: 'ERROR', message: 'Invalid game code' });
                return;
            }

            const { playerId, userId } = resolvePlayer(ws.id, authenticatedUsers, guestIds, msg.token);
            users.set(ws.id, playerId);

            const color = gameManager.joinGame(msg.gameId, playerId, userId);
            if (color) {
                ws.subscribe(msg.gameId);
                const game = gameManager.getGame(msg.gameId);
                const { whiteName, blackName } = await fetchPlayerNames(game);

                ws.send({
                    type: 'GAME_JOINED',
                    gameId: msg.gameId,
                    color,
                    fen: game?.fen,
                    timeRemaining: game?.timeRemaining,
                    history: game?.history || [],
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName
                });

                ws.publish(msg.gameId, JSON.stringify({
                    type: 'OPPONENT_JOINED',
                    opponentId: playerId,
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName
                }));

                app.server?.publish('lobby', JSON.stringify({
                    type: 'PENDING_GAMES_UPDATE',
                    games: gameManager.getPendingGames()
                }));
            } else {
                ws.send({ type: 'ERROR', message: 'Game full or invalid' });
            }

        } else if (msg.type === 'MOVE') {
            if (!isValidGameId(msg.gameId) || !isValidSquare(msg.from) || !isValidSquare(msg.to) || !isValidPromotion(msg.promotion)) {
                ws.send({ type: 'ERROR', message: 'Invalid move format' });
                return;
            }

            const playerId = users.get(ws.id);
            if (!playerId) {
                ws.send({ type: 'ERROR', message: 'Not in a game' });
                return;
            }

            const result = await gameManager.makeMove(msg.gameId, playerId, { from: msg.from, to: msg.to, promotion: msg.promotion });

            if (result.success && result.fen) {
                const payload = JSON.stringify({
                    type: 'UPDATE_BOARD',
                    fen: result.fen,
                    lastMove: { from: msg.from, to: msg.to },
                    timeRemaining: gameManager.getGame(msg.gameId)?.timeRemaining,
                    history: result.history || []
                });
                ws.publish(msg.gameId, payload);
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
                ws.send({ type: 'ERROR', message: result.error || 'Invalid move' });
            }

        } else if (msg.type === 'RESIGN') {
            if (!isValidGameId(msg.gameId)) return;
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.resign(msg.gameId, playerId);
            }

        } else if (msg.type === 'DRAW_OFFER') {
            if (!isValidGameId(msg.gameId)) return;
            const playerId = users.get(ws.id);
            if (playerId) {
                const color = gameManager.offerDraw(msg.gameId, playerId);
                if (color) {
                    ws.publish(msg.gameId, JSON.stringify({ type: 'DRAW_OFFER', color }));
                }
            }

        } else if (msg.type === 'DRAW_ACCEPT') {
            if (!isValidGameId(msg.gameId)) return;
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.acceptDraw(msg.gameId, playerId);
            }

        } else if (msg.type === 'DRAW_DECLINE') {
            if (!isValidGameId(msg.gameId)) return;
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
            const { playerId, userId } = resolvePlayer(ws.id, authenticatedUsers, guestIds, msg.token);
            users.set(ws.id, playerId);

            ws.subscribe(`user:${ws.id}`);

            const timeControl = typeof msg.timeControl === 'number' ? Math.min(Math.max(msg.timeControl, 1), 60) : 10;
            const result = gameManager.queueForMatch(playerId, userId, ws.id, timeControl);

            if (result.status === 'QUEUED') {
                ws.send({
                    type: 'QUEUE_STATUS',
                    status: 'QUEUED',
                    message: 'Looking for opponent...',
                    timeControl,
                });
            } else if (result.status === 'MATCHED') {
                const game = gameManager.getGame(result.gameId!);
                ws.subscribe(result.gameId!);
                const { whiteName, blackName } = await fetchPlayerNames(game);

                ws.send({
                    type: 'MATCH_FOUND',
                    gameId: result.gameId,
                    color: result.color,
                    fen: result.fen,
                    timeRemaining: result.timeRemaining,
                    history: game?.history || [],
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName,
                });

                if (result.opponentWsId) {
                    app.server?.publish(`user:${result.opponentWsId}`, JSON.stringify({
                        type: 'MATCH_FOUND',
                        gameId: result.gameId,
                        color: result.opponentColor,
                        fen: result.fen,
                        timeRemaining: result.timeRemaining,
                        history: game?.history || [],
                        whitePlayerName: whiteName,
                        blackPlayerName: blackName,
                    }));
                }
            }

        } else if (msg.type === 'CANCEL_QUEUE') {
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.removeFromQueue(playerId);
                ws.send({ type: 'QUEUE_CANCELLED' });
            }

        } else if (msg.type === 'SUBSCRIBE_GAME') {
            if (isValidGameId(msg.gameId)) {
                ws.subscribe(msg.gameId);
                ws.send({ type: 'SUBSCRIBED', gameId: msg.gameId });
            }

        } else if (msg.type === 'SYNC_TIME') {
            if (!isValidGameId(msg.gameId)) return;
            const playerId = users.get(ws.id);
            if (playerId) {
                gameManager.checkTimeout(msg.gameId);
            }

        } else if (msg.type === 'REJOIN_GAME') {
            const { playerId, userId } = resolvePlayer(ws.id, authenticatedUsers, guestIds, msg.token);

            if (!userId) {
                ws.send({ type: 'REJOIN_FAILED', message: 'Not authenticated' });
                return;
            }

            users.set(ws.id, playerId);

            const result = gameManager.rejoinGame(playerId, userId);

            if (result && result.success && result.gameId) {
                ws.subscribe(result.gameId);
                const game = gameManager.getGame(result.gameId);
                const { whiteName, blackName } = await fetchPlayerNames(game);

                ws.send({
                    type: 'REJOIN_SUCCESS',
                    gameId: result.gameId,
                    color: result.color,
                    fen: result.fen,
                    timeRemaining: result.timeRemaining,
                    history: result.history || [],
                    whitePlayerName: whiteName,
                    blackPlayerName: blackName,
                    opponentDisconnected: result.opponentDisconnected
                });

                console.log(`[WS] Player ${playerId} rejoined game ${result.gameId}`);
            } else {
                ws.send({ type: 'REJOIN_FAILED', message: 'No active game found' });
            }

        } else if (msg.type === 'CHAT_MESSAGE') {
            if (!isValidGameId(msg.gameId)) return;
            const playerId = users.get(ws.id);
            if (!playerId) return;

            const game = gameManager.getGame(msg.gameId);
            if (!game || game.status !== 'active') return;
            if (game.players.w !== playerId && game.players.b !== playerId) return;

            const chatMessage = typeof msg.message === 'string' ? msg.message.trim() : '';
            if (chatMessage.length === 0 || chatMessage.length > 200) return;
            if (containsProfanity(chatMessage)) {
                ws.send(JSON.stringify({ type: 'ERROR', message: 'Message contains inappropriate language' }));
                return;
            }

            const senderColor = game.players.w === playerId ? 'w' : 'b';
            let senderName = senderColor === 'w' ? 'White' : 'Black';
            const userId = authenticatedUsers.get(ws.id);
            if (userId) {
                const u = await User.findById(userId).select('username profile.displayName');
                if (u) senderName = (u as any).profile?.displayName || u.username;
            }

            const payload = JSON.stringify({
                type: 'CHAT_MESSAGE',
                gameId: msg.gameId,
                sender: senderColor,
                senderName,
                message: chatMessage,
                timestamp: Date.now()
            });
            ws.publish(msg.gameId, payload);
            ws.send(payload);

        } else {
            ws.send(JSON.stringify({ type: 'ERROR', message: `Unknown message type: ${msg.type}` }));
        }
    },
    close(ws) {
        console.log('Client disconnected:', ws.id);
        const playerId = users.get(ws.id);
        users.delete(ws.id);
        authenticatedUsers.delete(ws.id);
        guestIds.delete(ws.id);

        if (playerId) {
            gameManager.removeFromQueue(playerId);

            const activeGameId = gameManager.getActiveGameForPlayer(playerId);

            if (activeGameId) {
                const game = gameManager.getGame(activeGameId);
                if (game && (!game.players.w || !game.players.b)) {
                    const cleaned = gameManager.cleanupPendingGame(playerId);
                    if (cleaned) {
                        app.server?.publish('lobby', JSON.stringify({
                            type: 'PENDING_GAMES_UPDATE',
                            games: gameManager.getPendingGames()
                        }));
                    }
                } else {
                    gameManager.markPlayerDisconnected(playerId);
                }
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

            const game = await Game.findOne({ gameId });

            if (!game) {
                set.status = 404;
                return { error: 'Game not found' };
            }

            if (game.analysis?.evaluated) {
                return {
                    message: 'Game already analyzed',
                    analysis: game.analysis
                };
            }

            const chess = new Chess();
            const positions: Array<{ moveIndex: number; fen: string; san: string; color: string }> = [];

            positions.push({ moveIndex: 0, fen: chess.fen(), san: '', color: 'w' });

            for (let i = 0; i < game.moves.length; i++) {
                const uciMove = game.moves[i] as string;
                if (!uciMove || uciMove.length < 4) continue;

                const from = uciMove.slice(0, 2);
                const to = uciMove.slice(2, 4);
                const promotion = uciMove.length > 4 ? uciMove[4] : undefined;
                const color = i % 2 === 0 ? 'w' : 'b';

                const result = chess.move({ from, to, promotion });
                if (result) {
                    positions.push({
                        moveIndex: i + 1,
                        fen: chess.fen(),
                        san: result.san,
                        color
                    });
                }
            }

            const evaluations = [];
            let previousEval = 0;

            for (let i = 0; i < positions.length; i++) {
                const pos = positions[i];
                const { evaluation, bestMove } = await gameManager.botManager.getPositionEvaluation(pos.fen);

                let classification = null;
                if (i > 0) {
                    const currentEval = pos.color === 'b' ? -evaluation : evaluation;
                    const prevEval = positions[i - 1].color === 'b' ? -previousEval : previousEval;

                    const evalDrop = prevEval - currentEval;

                    if (evalDrop > 300) classification = 'blunder';
                    else if (evalDrop > 150) classification = 'mistake';
                    else if (evalDrop > 50) classification = 'inaccuracy';
                    else if (evalDrop < -100) classification = 'brilliant';
                    else if (evalDrop < -50) classification = 'great';
                    else if (evalDrop < -10) classification = 'good';
                    else classification = 'book';
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

            let whiteTotal = 0, whiteCount = 0;
            let blackTotal = 0, blackCount = 0;

            for (const ev of evaluations) {
                const score = ev.classification === 'blunder' ? 0 :
                              ev.classification === 'mistake' ? 25 :
                              ev.classification === 'inaccuracy' ? 50 :
                              ev.classification === 'good' ? 75 :
                              ev.classification === 'great' ? 90 :
                              ev.classification === 'brilliant' ? 100 : 85;

                const color = positions.find(p => p.moveIndex === ev.moveIndex)?.color;
                if (color === 'w') { whiteTotal += score; whiteCount++; }
                else if (color === 'b') { blackTotal += score; blackCount++; }
            }

            const whiteAccuracy = whiteCount > 0 ? Math.round(whiteTotal / whiteCount) : 100;
            const blackAccuracy = blackCount > 0 ? Math.round(blackTotal / blackCount) : 100;

            const keyMoments = evaluations.filter((ev: any) =>
                ['blunder', 'mistake', 'inaccuracy', 'brilliant', 'great'].includes(ev.classification)
            );

            game.analysis = {
                evaluated: true,
                accuracy: { w: whiteAccuracy, b: blackAccuracy },
                keyMoments: keyMoments as any,
                analyzedAt: new Date()
            };

            await game.save();

            return {
                message: 'Analysis complete',
                analysis: {
                    evaluated: true,
                    accuracy: { w: whiteAccuracy, b: blackAccuracy },
                    evaluations,
                    keyMoments,
                    analyzedAt: new Date()
                }
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

console.log(`Elysia is running at ${app.server?.hostname}:${app.server?.port}`);

// Periodic queue cleanup every 5 seconds
setInterval(() => {
    const timedOutWsIds = gameManager.cleanupStaleQueue();
    for (const wsId of timedOutWsIds) {
        app.server?.publish(`user:${wsId}`, JSON.stringify({
            type: 'QUEUE_TIMEOUT',
            message: 'No opponent found. Please try again.',
        }));
    }
}, 5000);

// Periodic disconnection cleanup every 10 seconds
setInterval(() => {
    const forfeits = gameManager.cleanupDisconnectedPlayers();
    for (const forfeit of forfeits) {
        console.log(`[Main] Player ${forfeit.forfeitPlayerId} forfeited game ${forfeit.gameId} due to disconnection timeout`);
    }
}, 10000);

// Periodic abandoned game cleanup every 5 minutes
setInterval(() => {
    const cleanedCount = gameManager.cleanupAbandonedGames();
    if (cleanedCount > 0) {
        console.log(`[Main] Cleaned up ${cleanedCount} abandoned games`);
    }
}, 5 * 60 * 1000);
