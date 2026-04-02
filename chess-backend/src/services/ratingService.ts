/**
 * Glicko-2 Rating System
 *
 * Based on Mark Glickman's paper:
 * http://www.glicko.net/glicko/glicko2.pdf
 *
 * Simplified for chess app with sensible defaults.
 */

const TAU = 0.5; // System constant (controls volatility change)
const EPSILON = 0.000001;
const GLICKO2_SCALE = 173.7178; // Converts between Glicko and Glicko-2 scales

interface GlickoPlayer {
    rating: number;        // Glicko rating (e.g., 1500)
    rd: number;            // Rating deviation (e.g., 350)
    volatility?: number;   // Rating volatility (default 0.06)
}

interface RatingResult {
    newRating: number;
    newRd: number;
    ratingChange: number;
}

// Convert Glicko rating to Glicko-2 scale
function toGlicko2(rating: number): number {
    return (rating - 1500) / GLICKO2_SCALE;
}

// Convert Glicko-2 rating back to Glicko scale
function fromGlicko2(mu: number): number {
    return mu * GLICKO2_SCALE + 1500;
}

// Convert Glicko RD to Glicko-2 scale
function rdToGlicko2(rd: number): number {
    return rd / GLICKO2_SCALE;
}

// Convert Glicko-2 RD back to Glicko scale
function rdFromGlicko2(phi: number): number {
    return phi * GLICKO2_SCALE;
}

// g(phi) function
function g(phi: number): number {
    return 1 / Math.sqrt(1 + 3 * phi * phi / (Math.PI * Math.PI));
}

// E(mu, mu_j, phi_j) - expected score
function E(mu: number, muJ: number, phiJ: number): number {
    return 1 / (1 + Math.exp(-g(phiJ) * (mu - muJ)));
}

/**
 * Calculate new rating after a single game using Glicko-2.
 *
 * @param player - The player whose rating to update
 * @param opponent - The opponent's rating info
 * @param score - 1 for win, 0.5 for draw, 0 for loss
 * @returns New rating, new RD, and rating change
 */
export function calculateNewRating(
    player: GlickoPlayer,
    opponent: GlickoPlayer,
    score: number
): RatingResult {
    const vol = player.volatility ?? 0.06;

    // Step 1: Convert to Glicko-2 scale
    const mu = toGlicko2(player.rating);
    const phi = rdToGlicko2(player.rd);
    const muJ = toGlicko2(opponent.rating);
    const phiJ = rdToGlicko2(opponent.rd);

    // Step 2: Compute variance (v)
    const gPhiJ = g(phiJ);
    const eVal = E(mu, muJ, phiJ);
    const v = 1 / (gPhiJ * gPhiJ * eVal * (1 - eVal));

    // Step 3: Compute estimated improvement (delta)
    const delta = v * gPhiJ * (score - eVal);

    // Step 4: Compute new volatility (simplified - use constant for single game)
    // Full iterative algorithm simplified for performance
    const newVol = vol; // Keep volatility stable for single-game updates

    // Step 5: Update rating deviation
    const phiStar = Math.sqrt(phi * phi + newVol * newVol);

    // Step 6: New phi and mu
    const newPhi = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
    const newMu = mu + newPhi * newPhi * gPhiJ * (score - eVal);

    // Convert back to Glicko scale
    const newRating = Math.round(fromGlicko2(newMu));
    const newRd = Math.round(rdFromGlicko2(newPhi));

    // Clamp rating to minimum 100
    const clampedRating = Math.max(100, newRating);
    // Clamp RD between 30 and 350
    const clampedRd = Math.max(30, Math.min(350, newRd));

    return {
        newRating: clampedRating,
        newRd: clampedRd,
        ratingChange: clampedRating - player.rating
    };
}

/**
 * Calculate rating changes for both players after a game.
 */
export function calculateGameRatings(
    white: GlickoPlayer,
    black: GlickoPlayer,
    winner: 'w' | 'b' | 'draw'
): { white: RatingResult; black: RatingResult } {
    const whiteScore = winner === 'w' ? 1 : winner === 'draw' ? 0.5 : 0;
    const blackScore = 1 - whiteScore;

    return {
        white: calculateNewRating(white, black, whiteScore),
        black: calculateNewRating(black, white, blackScore)
    };
}
