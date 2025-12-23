import { Elysia, t } from 'elysia';
import { User } from './schemas/user';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

export const auth = new Elysia({ prefix: '/auth' })
    .post('/register', async ({ body, set }) => {
        const { username, email, password } = body as any;

        try {
            const existingUser = await User.findOne({ $or: [{ username }, { email }] });
            if (existingUser) {
                set.status = 400;
                return { error: 'Username or email already exists' };
            }

            const passwordHash = await Bun.password.hash(password);

            const user = new User({
                username,
                email,
                passwordHash
            });

            await user.save();

            const token = jwt.sign({ id: user._id, username: user.username }, JWT_SECRET, { expiresIn: '7d' });

            return { token, user: { id: user._id, username: user.username, rating: user.rating } };
        } catch (error: any) {
            console.error('[Auth] Registration error:', error);
            set.status = 500;
            return { error: 'Registration failed', details: error.message };
        }
    }, {
        body: t.Object({
            username: t.String(),
            email: t.String(),
            password: t.String()
        })
    })
    .post('/login', async ({ body, set }) => {
        const { username, password } = body as any;

        try {
            const user = await User.findOne({ username });
            if (!user) {
                set.status = 400;
                return { error: 'Invalid credentials' };
            }

            const isMatch = await Bun.password.verify(password, user.passwordHash);
            if (!isMatch) {
                set.status = 400;
                return { error: 'Invalid credentials' };
            }

            const token = jwt.sign({ id: user._id, username: user.username }, JWT_SECRET, { expiresIn: '7d' });

            return { token, user: { id: user._id, username: user.username, rating: user.rating } };
        } catch (error) {
            set.status = 500;
            return { error: 'Login failed' };
        }
    }, {
        body: t.Object({
            username: t.String(),
            password: t.String()
        })
    })
    .get('/me', async ({ headers, set }) => {
        const authHeader = headers['authorization'];
        if (!authHeader) {
            set.status = 401;
            return { error: 'No token provided' };
        }

        const token = authHeader.replace('Bearer ', '');
        try {
            const decoded = jwt.verify(token, JWT_SECRET) as any;
            const user = await User.findById(decoded.id).select('-passwordHash');
            if (!user) {
                set.status = 404;
                return { error: 'User not found' };
            }
            return user;
        } catch (error) {
            set.status = 401;
            return { error: 'Invalid token' };
        }
    });
