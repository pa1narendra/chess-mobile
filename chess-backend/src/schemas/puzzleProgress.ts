import mongoose from 'mongoose';

/**
 * PuzzleProgress schema - tracks each user's puzzle solving history
 * - Puzzle content comes from Lichess public API (not stored here)
 * - We only track which puzzles a user has attempted and their rating
 */
const puzzleProgressSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
    puzzleRating: { type: Number, default: 1200 },
    solved: { type: Number, default: 0 },
    failed: { type: Number, default: 0 },
    streak: { type: Number, default: 0 },
    bestStreak: { type: Number, default: 0 },
    lastSolvedAt: { type: Date },
    // Daily puzzle tracking (so users don't get the same daily twice)
    lastDailyPuzzleDate: { type: String }, // YYYY-MM-DD
}, {
    timestamps: false
});

export const PuzzleProgress = mongoose.model('PuzzleProgress', puzzleProgressSchema);
