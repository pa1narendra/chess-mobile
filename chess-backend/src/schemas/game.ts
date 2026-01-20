import mongoose from 'mongoose';

/**
 * Optimized Game Schema
 *
 * Move storage strategy:
 * - `pgn`: Full PGN string for game export/display (e.g., "1. e4 e5 2. Nf3 Nc6")
 * - `moves`: Array of UCI strings for quick replay (e.g., ["e2e4", "e7e5", "g1f3"])
 *
 * Why UCI array instead of SAN array?
 * - UCI is fixed 4-5 chars (e2e4, e7e8q) - predictable size
 * - No ambiguity - directly playable without game state
 * - Engine compatible
 * - Color derived from index: even = white, odd = black
 */
const gameSchema = new mongoose.Schema({
    gameId: { type: String, required: true, unique: true },

    // Players - userIds for registered users
    userIds: {
        w: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        b: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
    },
    // Guest usernames (when not logged in)
    guestNames: {
        w: { type: String },
        b: { type: String }
    },

    // Game settings
    timeControl: {
        initial: { type: Number, default: 600000 }, // Initial time in ms
        increment: { type: Number, default: 0 }     // Increment per move in ms
    },
    isBot: { type: Boolean, default: false },
    botDifficulty: { type: Number, min: 1, max: 5 },
    isPrivate: { type: Boolean, default: false },

    // Game state
    status: {
        type: String,
        enum: ['waiting', 'active', 'finished', 'abandoned'],
        default: 'waiting'
    },
    fen: { type: String, required: true },  // Current/final position

    // Move storage (optimized)
    // UCI format: "e2e4", "e7e5", "g1f3", "e7e8q" (with promotion)
    // Color derived from index: moves[0] = white, moves[1] = black, etc.
    moves: [{ type: String, maxlength: 5 }],

    // PGN for export/display (generated on game end)
    pgn: { type: String },

    // Result
    result: {
        winner: { type: String, enum: ['w', 'b', null] },  // null = draw
        reason: {
            type: String,
            enum: ['checkmate', 'resignation', 'timeout', 'stalemate',
                   'insufficient', 'repetition', 'fifty-move', 'agreement', 'abandoned']
        }
    },

    // Time remaining at end of game
    timeRemaining: {
        w: { type: Number },
        b: { type: Number }
    },

    // Optional: Move timestamps for time-per-move analysis
    // Only stored if time control is enabled
    moveTimes: [{ type: Number }],  // Time taken per move in ms

    // Analysis (populated post-game)
    analysis: {
        evaluated: { type: Boolean, default: false },
        accuracy: {
            w: { type: Number },  // White's accuracy %
            b: { type: Number }   // Black's accuracy %
        },
        // Only store evaluations for key positions (mistakes/blunders)
        keyMoments: [{
            moveIndex: { type: Number },
            evaluation: { type: Number },      // Centipawns
            bestMove: { type: String },        // UCI
            classification: {
                type: String,
                enum: ['brilliant', 'great', 'best', 'excellent', 'good',
                       'inaccuracy', 'mistake', 'blunder']
            }
        }],
        analyzedAt: { type: Date }
    },

    // Timestamps
    createdAt: { type: Date, default: Date.now },
    startedAt: { type: Date },
    endedAt: { type: Date }
}, {
    timestamps: false  // We manage our own timestamps
});

// Indexes
gameSchema.index({ 'userIds.w': 1 });
gameSchema.index({ 'userIds.b': 1 });
gameSchema.index({ status: 1 });
gameSchema.index({ createdAt: -1 });  // For recent games queries
gameSchema.index({ 'userIds.w': 1, createdAt: -1 });  // User's recent games
gameSchema.index({ 'userIds.b': 1, createdAt: -1 });

export const Game = mongoose.model('Game', gameSchema);
