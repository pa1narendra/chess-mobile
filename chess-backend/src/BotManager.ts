import { Worker } from 'worker_threads';
import path from 'path';

export class BotManager {
    private engine: Worker;
    private isReady: boolean = false;

    constructor() {
        // Resolve path to stockfish.js
        // We assume it's in node_modules/stockfish.js/stockfish.js
        // or we can try to find it.
        const stockfishPath = path.join(process.cwd(), 'node_modules', 'stockfish.js', 'stockfish.js');

        console.log(`[BotManager] Initializing Stockfish worker from ${stockfishPath}`);
        this.engine = new Worker(stockfishPath);

        this.engine.on('message', (line: string) => {
            // console.log(`[Stockfish] ${line}`);
        });

        this.engine.on('error', (err) => {
            console.error(`[Stockfish] Worker error:`, err);
        });

        this.engine.on('exit', (code) => {
            if (code !== 0)
                console.error(`[Stockfish] Worker stopped with exit code ${code}`);
        });

        this.engine.postMessage('uci');
        this.engine.postMessage('isready');
    }

    async getBestMove(fen: string, difficulty: number): Promise<string> {
        return new Promise((resolve) => {
            // Configure difficulty
            // Skill Level is 0-20
            const skillLevel = Math.min(20, Math.max(0, (difficulty - 1) * 5));

            // Depth also matters
            const depths = [1, 3, 5, 8, 12];
            const depth = depths[Math.min(4, Math.max(0, difficulty - 1))];

            this.engine.postMessage(`setoption name Skill Level value ${skillLevel}`);
            this.engine.postMessage(`position fen ${fen}`);
            this.engine.postMessage(`go depth ${depth}`);

            const onMessage = (line: string) => {
                if (typeof line === 'string' && line.startsWith('bestmove')) {
                    const move = line.split(' ')[1];
                    this.engine.off('message', onMessage); // Remove listener
                    resolve(move);
                }
            };

            this.engine.on('message', onMessage);
        });
    }

    async getPositionEvaluation(fen: string, depth: number = 12): Promise<{ evaluation: number; bestMove: string }> {
        return new Promise((resolve) => {
            let evaluation = 0;
            let bestMove = '';

            // Reset skill level to maximum for accurate analysis
            this.engine.postMessage('setoption name Skill Level value 20');
            this.engine.postMessage(`position fen ${fen}`);
            this.engine.postMessage(`go depth ${depth}`);

            const onMessage = (line: string) => {
                if (typeof line === 'string') {
                    // Parse evaluation from "info" lines
                    // Example: "info depth 12 score cp 150 ..."
                    if (line.includes('info') && line.includes('score')) {
                        const scoreCpMatch = line.match(/score cp (-?\d+)/);
                        const scoreMateMatch = line.match(/score mate (-?\d+)/);

                        if (scoreMateMatch) {
                            // Mate score: convert to large centipawn value
                            const mateIn = parseInt(scoreMateMatch[1]);
                            evaluation = mateIn > 0 ? 10000 - mateIn * 100 : -10000 - mateIn * 100;
                        } else if (scoreCpMatch) {
                            evaluation = parseInt(scoreCpMatch[1]);
                        }
                    }

                    // Get best move
                    if (line.startsWith('bestmove')) {
                        bestMove = line.split(' ')[1];
                        this.engine.off('message', onMessage);
                        resolve({ evaluation, bestMove });
                    }
                }
            };

            this.engine.on('message', onMessage);
        });
    }
}
