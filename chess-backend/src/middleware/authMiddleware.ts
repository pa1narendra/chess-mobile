import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
    throw new Error('JWT_SECRET environment variable is required. Server cannot start without it.');
}

export { JWT_SECRET };

/**
 * Verifies a Bearer token from the Authorization header.
 * Returns the decoded payload or null if invalid.
 */
export function verifyAuthHeader(authHeader: string | undefined): { id: string; username: string } | null {
    if (!authHeader) return null;

    const token = authHeader.replace('Bearer ', '');
    try {
        const decoded = jwt.verify(token, JWT_SECRET!) as { id: string; username: string };
        if (!decoded.id) return null;
        return decoded;
    } catch {
        return null;
    }
}

/**
 * Verifies a raw JWT token string.
 * Returns the decoded payload or null if invalid.
 */
export function verifyToken(token: string | undefined): { id: string; username: string } | null {
    if (!token) return null;

    try {
        const decoded = jwt.verify(token, JWT_SECRET!) as { id: string; username: string };
        if (!decoded.id) return null;
        return decoded;
    } catch {
        return null;
    }
}
