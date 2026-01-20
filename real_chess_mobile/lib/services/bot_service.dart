import 'dart:async';
import 'dart:math';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter/foundation.dart';

// Data class to pass to isolate (must be top-level for compute())
class _BotCalculationParams {
  final String fen;
  final int depth;
  final double randomness;

  _BotCalculationParams(this.fen, this.depth, this.randomness);
}

// Top-level function for compute() - runs in isolate
String _calculateBestMove(_BotCalculationParams params) {
  final random = Random();
  final chess = chess_lib.Chess.fromFEN(params.fen);
  final moves = chess.generate_moves();

  if (moves.isEmpty) {
    throw Exception('No legal moves available');
  }

  // Chance to make a random move based on difficulty
  if (random.nextDouble() < params.randomness) {
    final randomMove = moves[random.nextInt(moves.length)];
    return _staticMoveToUci(randomMove);
  }

  // Find best move using minimax
  String? bestMove;
  int bestValue = -999999;
  final isMaximizing = chess.turn == chess_lib.Color.WHITE;

  for (final move in moves) {
    chess.move(move);
    final value = _staticMinimax(
      chess,
      params.depth - 1,
      -1000000,
      1000000,
      !isMaximizing,
    );
    chess.undo();

    final adjustedValue = isMaximizing ? value : -value;
    if (adjustedValue > bestValue) {
      bestValue = adjustedValue;
      bestMove = _staticMoveToUci(move);
    }
  }

  return bestMove ?? _staticMoveToUci(moves[0]);
}

// Static minimax for isolate
int _staticMinimax(chess_lib.Chess chess, int depth, int alpha, int beta, bool isMaximizing) {
  if (depth == 0 || chess.game_over) {
    return _staticEvaluateBoard(chess);
  }

  final moves = chess.generate_moves();

  if (isMaximizing) {
    int maxEval = -999999;
    for (final move in moves) {
      chess.move(move);
      final eval = _staticMinimax(chess, depth - 1, alpha, beta, false);
      chess.undo();
      if (eval > maxEval) maxEval = eval;
      if (eval > alpha) alpha = eval;
      if (beta <= alpha) break;
    }
    return maxEval;
  } else {
    int minEval = 999999;
    for (final move in moves) {
      chess.move(move);
      final eval = _staticMinimax(chess, depth - 1, alpha, beta, true);
      chess.undo();
      if (eval < minEval) minEval = eval;
      if (eval < beta) beta = eval;
      if (beta <= alpha) break;
    }
    return minEval;
  }
}

int _staticEvaluateBoard(chess_lib.Chess chess) {
  if (chess.in_checkmate) {
    return chess.turn == chess_lib.Color.WHITE ? -100000 : 100000;
  }
  if (chess.in_stalemate || chess.in_draw) {
    return 0;
  }

  int score = 0;

  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      final piece = chess.board[row * 16 + col];
      if (piece != null) {
        final pieceValue = _staticGetPieceValue(piece.type);
        if (piece.color == chess_lib.Color.WHITE) {
          score += pieceValue;
        } else {
          score -= pieceValue;
        }
      }
    }
  }

  return score;
}

int _staticGetPieceValue(chess_lib.PieceType type) {
  switch (type) {
    case chess_lib.PieceType.PAWN:
      return 100;
    case chess_lib.PieceType.KNIGHT:
      return 320;
    case chess_lib.PieceType.BISHOP:
      return 330;
    case chess_lib.PieceType.ROOK:
      return 500;
    case chess_lib.PieceType.QUEEN:
      return 900;
    case chess_lib.PieceType.KING:
      return 20000;
    default:
      return 0;
  }
}

String _staticMoveToUci(chess_lib.Move move) {
  final from = move.fromAlgebraic;
  final to = move.toAlgebraic;
  final promotion = move.promotion != null ? move.promotion!.name.toLowerCase() : '';
  return '$from$to$promotion';
}

enum BotDifficulty {
  beginner(depth: 1, randomness: 0.4),
  easy(depth: 2, randomness: 0.25),
  medium(depth: 3, randomness: 0.1),
  hard(depth: 4, randomness: 0.05),
  expert(depth: 5, randomness: 0.0);

  final int depth;
  final double randomness; // Chance to make a random move instead of best move

  const BotDifficulty({
    required this.depth,
    required this.randomness,
  });

  static BotDifficulty fromLevel(int level) {
    switch (level) {
      case 1:
        return BotDifficulty.beginner;
      case 2:
        return BotDifficulty.easy;
      case 3:
        return BotDifficulty.medium;
      case 4:
        return BotDifficulty.hard;
      case 5:
        return BotDifficulty.expert;
      default:
        return BotDifficulty.medium;
    }
  }

  String get displayName {
    switch (this) {
      case BotDifficulty.beginner:
        return 'Beginner';
      case BotDifficulty.easy:
        return 'Easy';
      case BotDifficulty.medium:
        return 'Medium';
      case BotDifficulty.hard:
        return 'Hard';
      case BotDifficulty.expert:
        return 'Expert';
    }
  }
}

/// Pure Dart chess AI using minimax algorithm with alpha-beta pruning
/// Heavy computation runs in a background isolate to avoid UI lag
class LocalBotService {
  bool _isInitialized = false;
  bool _isThinking = false;

  bool get isInitialized => _isInitialized;
  bool get isThinking => _isThinking;

  Future<void> initialize() async {
    _isInitialized = true;
  }

  Future<String> getBestMove(String fen, BotDifficulty difficulty) async {
    if (_isThinking) {
      throw Exception('Bot is already thinking');
    }

    _isThinking = true;

    try {
      debugPrint('[BotService] Starting calculation in background isolate...');
      debugPrint('[BotService] FEN: $fen, Depth: ${difficulty.depth}');

      // Run heavy calculation in background isolate to avoid UI lag
      final bestMove = await compute(
        _calculateBestMove,
        _BotCalculationParams(fen, difficulty.depth, difficulty.randomness),
      );

      debugPrint('[BotService] Best move: $bestMove');
      return bestMove;
    } finally {
      _isThinking = false;
    }
  }

  void stopThinking() {
    // No-op for pure Dart implementation
  }

  void dispose() {
    _isInitialized = false;
  }
}
