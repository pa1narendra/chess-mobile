import mongoose from 'mongoose';

const gameSchema = new mongoose.Schema({
    gameId: { type: String, required: true, unique: true },
    // Track userId for registered users (references to User._id)
    players: {
        w: { type: String },
        b: { type: String }
    },
    userIds: {
        w: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        b: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
    },
    // Game settings
    timeControl: {
        initial: { type: Number, default: 600000 }, // Initial time in ms (default 10 min)
        increment: { type: Number, default: 0 }     // Increment per move in ms
    },
    isBot: { type: Boolean, default: false },
    botDifficulty: { type: Number, default: 1 },
    isPrivate: { type: Boolean, default: false },
    // Game state
    status: { type: String, enum: ['waiting', 'active', 'finished', 'abandoned'], default: 'waiting' },
    fen: { type: String, required: true },
    pgn: { type: String },
    moves: [{
        from: String,
        to: String,
        promotion: String,
        san: String,
        color: String,
        timestamp: { type: Date, default: Date.now }
    }],
    result: {
        winner: { type: String, enum: ['w', 'b', 'draw', null], default: null },
        reason: { type: String, default: null }
    },
    // Time tracking
    timeRemaining: {
        w: { type: Number },
        b: { type: Number }
    },
    analysis: {
        evaluated: { type: Boolean, default: false },
        evaluations: [{
            moveIndex: { type: Number },
            fen: { type: String },
            evaluation: { type: Number },  // Centipawns
            bestMove: { type: String },    // UCI notation
            classification: { type: String, enum: ['brilliant', 'great', 'good', 'book', 'inaccuracy', 'mistake', 'blunder', null] }
        }],
        analyzedAt: { type: Date }
    },
    createdAt: { type: Date, default: Date.now },
    startedAt: { type: Date },  // When both players joined and game started
    endedAt: { type: Date },    // When game finished
    updatedAt: { type: Date, default: Date.now }
});

// Indexes for better query performance
// gameId is already indexed by unique: true
gameSchema.index({ 'players.w': 1 });
gameSchema.index({ 'players.b': 1 });
gameSchema.index({ 'userIds.w': 1 });
gameSchema.index({ 'userIds.b': 1 });

export const Game = mongoose.model('Game', gameSchema);
