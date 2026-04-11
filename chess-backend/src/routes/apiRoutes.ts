import { Elysia, t } from 'elysia';
import mongoose from 'mongoose';
import { Game } from '../schemas/game';
import { User } from '../schemas/user';
import { Friendship } from '../schemas/friendship';
import { PuzzleProgress } from '../schemas/puzzleProgress';
import { verifyAuthHeader } from '../middleware/authMiddleware';

export const apiRoutes = new Elysia({ prefix: '/api' })

    // GET /api/games/history - Get authenticated user's game history
    .get('/games/history', async ({ headers, set, query }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const page = parseInt(query.page || '1');
        const pageSize = Math.min(parseInt(query.pageSize || '20'), 50);
        const skip = (page - 1) * pageSize;

        const filter = {
            $or: [{ 'userIds.w': user.id }, { 'userIds.b': user.id }],
            status: 'finished'
        };

        const [games, total] = await Promise.all([
            Game.find(filter)
                .sort({ endedAt: -1, createdAt: -1 })
                .skip(skip)
                .limit(pageSize)
                .select('gameId userIds result timeControl isBot botDifficulty createdAt endedAt moves fen analysis.accuracy')
                .lean(),
            Game.countDocuments(filter)
        ]);

        // Enrich with opponent usernames
        const enriched = await Promise.all(games.map(async (game: any) => {
            const isWhite = game.userIds?.w?.toString() === user.id;
            const opponentId = isWhite ? game.userIds?.b : game.userIds?.w;
            let opponentName = game.isBot ? `Bot` : 'Guest';

            if (opponentId) {
                const opponent = await User.findById(opponentId).select('username rating profile.displayName').lean();
                if (opponent) opponentName = (opponent as any).profile?.displayName || (opponent as any).username;
            }

            const playerColor = isWhite ? 'w' : 'b';
            const playerResult = game.result?.winner === 'draw' ? 'draw'
                : game.result?.winner === playerColor ? 'win' : 'loss';

            return {
                gameId: game.gameId,
                playerColor,
                result: playerResult,
                reason: game.result?.reason,
                opponentName,
                isBot: game.isBot,
                botDifficulty: game.botDifficulty,
                timeControl: game.timeControl,
                movesCount: game.moves?.length || 0,
                accuracy: game.analysis?.accuracy,
                createdAt: game.createdAt,
                endedAt: game.endedAt
            };
        }));

        return {
            success: true,
            data: enriched,
            pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) }
        };
    }, {
        query: t.Object({
            page: t.Optional(t.String()),
            pageSize: t.Optional(t.String())
        })
    })

    // DELETE /api/games/history - Clear all finished games for authenticated user
    .delete('/games/history', async ({ headers, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const result = await Game.deleteMany({
            $or: [{ 'userIds.w': user.id }, { 'userIds.b': user.id }],
            status: 'finished'
        });

        return { success: true, deleted: result.deletedCount };
    })

    // GET /api/games/:gameId/details - Get full game details for replay
    .get('/games/:gameId/details', async ({ params, set }) => {
        const game = await Game.findOne({ gameId: params.gameId })
            .select('gameId userIds result timeControl moves pgn fen analysis createdAt endedAt isBot botDifficulty')
            .lean();

        if (!game) {
            set.status = 404;
            return { error: 'Game not found' };
        }

        // Fetch player names
        let whiteName = 'White';
        let blackName = 'Black';
        const g = game as any;

        if (g.isBot) {
            blackName = 'Bot';
        }
        if (g.userIds?.w) {
            const u = await User.findById(g.userIds.w).select('username rating profile.displayName').lean();
            if (u) whiteName = (u as any).profile?.displayName || (u as any).username;
        }
        if (g.userIds?.b) {
            const u = await User.findById(g.userIds.b).select('username rating profile.displayName').lean();
            if (u) blackName = (u as any).profile?.displayName || (u as any).username;
        }

        return {
            success: true,
            data: {
                ...g,
                whiteName,
                blackName
            }
        };
    })

    // GET /api/leaderboard - Get top players by rating
    .get('/leaderboard', async ({ query }) => {
        const page = parseInt(query.page || '1');
        const pageSize = Math.min(parseInt(query.pageSize || '20'), 50);
        const skip = (page - 1) * pageSize;

        const [players, total] = await Promise.all([
            User.find({
                $or: [
                    { 'stats.games': { $gt: 0 } },
                    { gamesPlayed: { $gt: 0 } }
                ]
            })
                .sort({ rating: -1 })
                .skip(skip)
                .limit(pageSize)
                .select('username rating peakRating stats gamesPlayed wins losses draws profile.country profile.avatar profile.displayName')
                .lean(),
            User.countDocuments({
                $or: [
                    { 'stats.games': { $gt: 0 } },
                    { gamesPlayed: { $gt: 0 } }
                ]
            })
        ]);

        const ranked = players.map((p: any, i: number) => {
            const games = p.stats?.games || p.gamesPlayed || 0;
            const wins = p.stats?.wins || p.wins || 0;
            const losses = p.stats?.losses || p.losses || 0;
            const draws = p.stats?.draws || p.draws || 0;
            return {
                rank: skip + i + 1,
                username: p.profile?.displayName || p.username,
                rating: p.rating,
                peakRating: p.peakRating,
                gamesPlayed: games,
                wins,
                losses,
                draws,
                winRate: games > 0 ? Math.round((wins / games) * 100) : 0,
                country: p.profile?.country,
                avatar: p.profile?.avatar
            };
        });

        return {
            success: true,
            data: ranked,
            pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) }
        };
    }, {
        query: t.Object({
            page: t.Optional(t.String()),
            pageSize: t.Optional(t.String())
        })
    })

    // GET /api/users/:id/profile - Get user profile
    .get('/users/:id/profile', async ({ params, set }) => {
        const user = await User.findById(params.id)
            .select('-passwordHash')
            .lean();

        if (!user) {
            set.status = 404;
            return { error: 'User not found' };
        }

        // Get user's rank
        const u = user as any;
        const rank = await User.countDocuments({
            rating: { $gt: u.rating },
            $or: [
                { 'stats.games': { $gt: 0 } },
                { gamesPlayed: { $gt: 0 } }
            ]
        }) + 1;

        // Get recent games count
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const recentGames = await Game.countDocuments({
            $or: [{ 'userIds.w': params.id }, { 'userIds.b': params.id }],
            status: 'finished',
            endedAt: { $gte: thirtyDaysAgo }
        });

        return {
            success: true,
            data: {
                _id: u._id,
                username: u.username,
                profile: u.profile,
                rating: u.rating,
                ratingDeviation: u.ratingDeviation,
                peakRating: u.peakRating,
                ratingHistory: u.ratingHistory,
                stats: {
                    games: u.stats?.games || u.gamesPlayed || 0,
                    wins: u.stats?.wins || u.wins || 0,
                    losses: u.stats?.losses || u.losses || 0,
                    draws: u.stats?.draws || u.draws || 0,
                    currentStreak: u.stats?.currentStreak || 0,
                    bestStreak: u.stats?.bestStreak || 0,
                },
                rank,
                recentGames,
                createdAt: u.createdAt,
                lastActive: u.lastActive
            }
        };
    })

    // PUT /api/users/profile - Update own profile
    .put('/users/profile', async ({ headers, body, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const updates: any = {};
        if (body.displayName !== undefined) updates['profile.displayName'] = body.displayName.slice(0, 30);
        if (body.bio !== undefined) updates['profile.bio'] = body.bio.slice(0, 200);
        if (body.country !== undefined) updates['profile.country'] = body.country.slice(0, 2).toUpperCase();
        if (body.avatar !== undefined) updates['profile.avatar'] = body.avatar;

        const updated = await User.findByIdAndUpdate(
            user.id,
            { $set: updates },
            { new: true }
        ).select('-passwordHash').lean();

        if (!updated) {
            set.status = 404;
            return { error: 'User not found' };
        }

        return { success: true, data: updated };
    }, {
        body: t.Object({
            displayName: t.Optional(t.String()),
            bio: t.Optional(t.String()),
            country: t.Optional(t.String()),
            avatar: t.Optional(t.String())
        })
    })

    // POST /api/admin/migrate-stats - One-time migration to sync old flat stats into nested stats
    .post('/admin/migrate-stats', async ({ headers, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const users = await User.find({}).lean();
        let migrated = 0;

        for (const u of users as any[]) {
            const oldGames = u.gamesPlayed || 0;
            const oldWins = u.wins || 0;
            const oldLosses = u.losses || 0;
            const oldDraws = u.draws || 0;
            const currentStats = u.stats || {};

            // Only migrate if nested stats are empty but flat fields have data
            if ((currentStats.games || 0) === 0 && oldGames > 0) {
                await User.findByIdAndUpdate(u._id, {
                    $set: {
                        'stats.games': oldGames,
                        'stats.wins': oldWins,
                        'stats.losses': oldLosses,
                        'stats.draws': oldDraws,
                        peakRating: Math.max(u.peakRating || 1200, u.rating || 1200),
                    }
                });
                migrated++;
            }

            // Fix peakRating if current rating is higher
            if ((u.rating || 1200) > (u.peakRating || 1200)) {
                await User.findByIdAndUpdate(u._id, {
                    $set: { peakRating: u.rating }
                });
                migrated++;
            }
        }

        return { success: true, migrated };
    })

    // --- FRIENDS ENDPOINTS ---

    // GET /api/users/search?q=username - Search users by username
    .get('/users/search', async ({ headers, query, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const q = (query.q || '').trim();
        if (q.length < 2) return { success: true, data: [] };

        const users = await User.find({
            username: { $regex: q, $options: 'i' },
            _id: { $ne: user.id }
        })
            .limit(20)
            .select('username rating profile.displayName profile.country')
            .lean();

        return {
            success: true,
            data: users.map((u: any) => ({
                _id: u._id,
                username: u.username,
                displayName: u.profile?.displayName,
                rating: u.rating,
                country: u.profile?.country,
            }))
        };
    }, {
        query: t.Object({ q: t.Optional(t.String()) })
    })

    // GET /api/friends - List authenticated user's friends and pending requests
    .get('/friends', async ({ headers, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const userId = new mongoose.Types.ObjectId(user.id);

        // Accepted friendships — could be either requester or recipient
        const accepted = await Friendship.find({
            $or: [{ requester: userId }, { recipient: userId }],
            status: 'accepted'
        }).lean();

        // Pending requests where I am the recipient
        const incoming = await Friendship.find({
            recipient: userId,
            status: 'pending'
        }).lean();

        // Pending requests I sent
        const outgoing = await Friendship.find({
            requester: userId,
            status: 'pending'
        }).lean();

        // Helper: fetch users for a list of IDs
        const fetchUsers = async (ids: any[]) => {
            if (ids.length === 0) return [];
            const users = await User.find({ _id: { $in: ids } })
                .select('username rating profile.displayName profile.country isOnline lastActive')
                .lean();
            return users.map((u: any) => ({
                _id: u._id,
                username: u.username,
                displayName: u.profile?.displayName,
                rating: u.rating,
                country: u.profile?.country,
                isOnline: u.isOnline,
                lastActive: u.lastActive,
            }));
        };

        const friendIds = accepted.map((f: any) =>
            f.requester.toString() === user.id ? f.recipient : f.requester
        );
        const incomingIds = incoming.map((f: any) => f.requester);
        const outgoingIds = outgoing.map((f: any) => f.recipient);

        const [friends, incomingUsers, outgoingUsers] = await Promise.all([
            fetchUsers(friendIds),
            fetchUsers(incomingIds),
            fetchUsers(outgoingIds),
        ]);

        // Attach friendship ID for incoming requests (needed for accept/decline)
        const incomingWithId = incomingUsers.map((u: any) => {
            const f = incoming.find((fr: any) => fr.requester.toString() === u._id.toString());
            return { ...u, friendshipId: f?._id };
        });

        return {
            success: true,
            data: { friends, incoming: incomingWithId, outgoing: outgoingUsers }
        };
    })

    // POST /api/friends/request - Send friend request
    .post('/friends/request', async ({ headers, body, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const targetId = body.userId;
        if (!mongoose.Types.ObjectId.isValid(targetId)) {
            set.status = 400;
            return { error: 'Invalid user ID' };
        }
        if (targetId === user.id) {
            set.status = 400;
            return { error: "Can't friend yourself" };
        }

        // Check if target user exists
        const target = await User.findById(targetId).select('_id');
        if (!target) {
            set.status = 404;
            return { error: 'User not found' };
        }

        const requester = new mongoose.Types.ObjectId(user.id);
        const recipient = new mongoose.Types.ObjectId(targetId);

        // Check if friendship already exists in either direction
        const existing = await Friendship.findOne({
            $or: [
                { requester, recipient },
                { requester: recipient, recipient: requester }
            ]
        });
        if (existing) {
            if (existing.status === 'accepted') {
                return { success: false, error: 'Already friends' };
            }
            return { success: false, error: 'Friend request already exists' };
        }

        const friendship = new Friendship({ requester, recipient, status: 'pending' });
        await friendship.save();

        return { success: true, data: { friendshipId: friendship._id } };
    }, {
        body: t.Object({ userId: t.String() })
    })

    // PUT /api/friends/:id/accept - Accept friend request
    .put('/friends/:id/accept', async ({ headers, params, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        if (!mongoose.Types.ObjectId.isValid(params.id)) {
            set.status = 400;
            return { error: 'Invalid friendship ID' };
        }

        const friendship = await Friendship.findById(params.id);
        if (!friendship) {
            set.status = 404;
            return { error: 'Friend request not found' };
        }

        // Only recipient can accept
        if (friendship.recipient.toString() !== user.id) {
            set.status = 403;
            return { error: 'Not authorized' };
        }
        if (friendship.status === 'accepted') {
            return { success: true };
        }

        friendship.status = 'accepted';
        friendship.acceptedAt = new Date();
        await friendship.save();

        return { success: true };
    })

    // DELETE /api/friends/:id - Remove friend or decline/cancel request
    .delete('/friends/:id', async ({ headers, params, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        if (!mongoose.Types.ObjectId.isValid(params.id)) {
            set.status = 400;
            return { error: 'Invalid friendship ID' };
        }

        const friendship = await Friendship.findById(params.id);
        if (!friendship) {
            set.status = 404;
            return { error: 'Friendship not found' };
        }

        // Either side can remove
        if (friendship.requester.toString() !== user.id && friendship.recipient.toString() !== user.id) {
            set.status = 403;
            return { error: 'Not authorized' };
        }

        await Friendship.findByIdAndDelete(params.id);
        return { success: true };
    })

    // --- PUZZLES ---
    // We proxy Lichess's public puzzle API so we don't need our own puzzle database.
    // Lichess has ~4M community-contributed puzzles. CC0 licensed.

    // GET /api/puzzles/daily - Today's puzzle (same for everyone)
    .get('/puzzles/daily', async ({ set }) => {
        try {
            const response = await fetch('https://lichess.org/api/puzzle/daily');
            if (!response.ok) {
                set.status = 502;
                return { error: 'Puzzle service unavailable' };
            }
            const data = await response.json();
            return { success: true, data };
        } catch (e: any) {
            set.status = 500;
            return { error: e.message || 'Failed to fetch daily puzzle' };
        }
    })

    // GET /api/puzzles/random - Random puzzle, optionally near user's puzzle rating
    .get('/puzzles/random', async ({ headers, query, set }) => {
        try {
            // Lichess random puzzle endpoint (public, no auth needed)
            // Supported parameters: angle (theme), difficulty (easy/normal/hard)
            const difficulty = query.difficulty || 'normal';
            const url = `https://lichess.org/api/puzzle/next?difficulty=${difficulty}`;

            const response = await fetch(url);
            if (!response.ok) {
                set.status = 502;
                return { error: 'Puzzle service unavailable' };
            }
            const data = await response.json();
            return { success: true, data };
        } catch (e: any) {
            set.status = 500;
            return { error: e.message || 'Failed to fetch puzzle' };
        }
    }, {
        query: t.Object({
            difficulty: t.Optional(t.String())
        })
    })

    // GET /api/puzzles/progress - Get authenticated user's puzzle stats
    .get('/puzzles/progress', async ({ headers, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        let progress = await PuzzleProgress.findOne({ userId: user.id }).lean();
        if (!progress) {
            // Create default progress on first access
            const created = await PuzzleProgress.create({ userId: user.id });
            progress = created.toObject();
        }

        return { success: true, data: progress };
    })

    // POST /api/puzzles/solved - Record puzzle result
    .post('/puzzles/solved', async ({ headers, body, set }) => {
        const user = verifyAuthHeader(headers['authorization']);
        if (!user) {
            set.status = 401;
            return { error: 'Authentication required' };
        }

        const { success: solved, puzzleRating } = body;
        const userId = new mongoose.Types.ObjectId(user.id);

        let progress = await PuzzleProgress.findOne({ userId });
        if (!progress) {
            progress = new PuzzleProgress({ userId });
        }

        // Simple Glicko-like rating adjustment
        // expected score based on rating difference
        const kFactor = 32;
        const currentRating = progress.puzzleRating || 1200;
        const expectedScore = 1 / (1 + Math.pow(10, ((puzzleRating || 1500) - currentRating) / 400));
        const actualScore = solved ? 1 : 0;
        const ratingChange = Math.round(kFactor * (actualScore - expectedScore));

        progress.puzzleRating = currentRating + ratingChange;

        if (solved) {
            progress.solved = (progress.solved || 0) + 1;
            progress.streak = (progress.streak || 0) + 1;
            if (progress.streak > (progress.bestStreak || 0)) {
                progress.bestStreak = progress.streak;
            }
            progress.lastSolvedAt = new Date();
        } else {
            progress.failed = (progress.failed || 0) + 1;
            progress.streak = 0;
        }

        await progress.save();
        return { success: true, data: { newRating: progress.puzzleRating, ratingChange } };
    }, {
        body: t.Object({
            success: t.Boolean(),
            puzzleRating: t.Optional(t.Number())
        })
    });
