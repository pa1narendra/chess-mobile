import mongoose from 'mongoose';

const connectDB = async () => {
    try {
        console.log('Connecting to MongoDB...');
        console.log('URI:', process.env.MONGO_URI?.substring(0, 20) + '...');
        console.log('DB Name:', process.env.DB_NAME);

        await mongoose.connect(process.env.MONGO_URI || '', {
            serverSelectionTimeoutMS: 30000, // Increased to 30 seconds for Atlas cold start
            socketTimeoutMS: 45000
        });
        console.log('MongoDB Connected Successfully');
        console.log('Connection state:', mongoose.connection.readyState); // 1 = connected
    } catch (error: any) {
        console.error('MongoDB connection error:', error.message);
        console.error('Full error:', error);
        // Don't exit, just log. This allows the server to start even if DB fails, though DB ops will fail.
    }
};

export default connectDB;
