import mongoose from 'mongoose';

/**
 * Optimized User Schema
 *
 * Stats are denormalized for quick access (no need to aggregate games collection)
 * Rating history stored for graphs/progression tracking
 */
const userSchema = new mongoose.Schema({
    // Auth
    username: {
        type: String,
        required: true,
        unique: true,
        minlength: 3,
        maxlength: 20,
        match: /^[a-zA-Z0-9_]+$/  // Alphanumeric + underscore only
    },
    email: {
        type: String,
        required: true,
        unique: true,
        lowercase: true
    },
    passwordHash: { type: String, required: true },

    // Profile
    profile: {
        displayName: { type: String, maxlength: 30 },
        avatar: { type: String },  // URL or avatar ID
        country: { type: String, maxlength: 2 },  // ISO country code
        bio: { type: String, maxlength: 200 }
    },

    // Rating (Elo-based)
    rating: { type: Number, default: 1200 },
    ratingDeviation: { type: Number, default: 350 },  // For Glicko-2
    peakRating: { type: Number, default: 1200 },

    // Rating history (last 30 data points for graph)
    // Each entry: { rating, date }
    ratingHistory: [{
        r: { type: Number },  // rating (short key to save space)
        d: { type: Date }     // date
    }],

    // Stats (denormalized for quick access)
    stats: {
        games: { type: Number, default: 0 },
        wins: { type: Number, default: 0 },
        losses: { type: Number, default: 0 },
        draws: { type: Number, default: 0 },
        // Streaks
        currentStreak: { type: Number, default: 0 },  // Positive = wins, negative = losses
        bestStreak: { type: Number, default: 0 }
    },

    // Preferences
    preferences: {
        boardTheme: { type: String, default: 'brown' },
        pieceSet: { type: String, default: 'standard' },
        soundEnabled: { type: Boolean, default: true },
        autoQueen: { type: Boolean, default: true },  // Auto-promote to queen
        showLegalMoves: { type: Boolean, default: true }
    },

    // Activity tracking
    lastActive: { type: Date, default: Date.now },
    isOnline: { type: Boolean, default: false },

    // Timestamps
    createdAt: { type: Date, default: Date.now }
}, {
    timestamps: false
});

// Indexes (username/email already indexed via unique: true)
userSchema.index({ rating: -1 });   // For leaderboard
userSchema.index({ lastActive: -1 });  // For "online players" queries

// Virtual for win rate
userSchema.virtual('winRate').get(function() {
    if (this.stats.games === 0) return 0;
    return Math.round((this.stats.wins / this.stats.games) * 100);
});

// Method to update rating history (keep last 30)
userSchema.methods.addRatingHistory = function(newRating: number) {
    this.ratingHistory.push({ r: newRating, d: new Date() });
    if (this.ratingHistory.length > 30) {
        this.ratingHistory.shift();  // Remove oldest
    }
    if (newRating > this.peakRating) {
        this.peakRating = newRating;
    }
};

export const User = mongoose.model('User', userSchema);
