import mongoose from 'mongoose';

/**
 * Friendship schema
 * - Represents a relationship between two users
 * - `requester` sent the request, `recipient` is the target
 * - `status`: 'pending' | 'accepted'
 * - Once accepted, either side can query friends via either field
 */
const friendshipSchema = new mongoose.Schema({
    requester: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    recipient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    status: {
        type: String,
        enum: ['pending', 'accepted'],
        default: 'pending',
        index: true
    },
    createdAt: { type: Date, default: Date.now },
    acceptedAt: { type: Date }
}, {
    timestamps: false
});

// Compound index: only one friendship between any two users
friendshipSchema.index({ requester: 1, recipient: 1 }, { unique: true });

export const Friendship = mongoose.model('Friendship', friendshipSchema);
