import 'dart:async';
import 'dart:math';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter/foundation.dart';

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
class LocalBotService {
  final Random _random = Random();
  bool _isInitialized = false;
  bool _isThinking = false;

  bool get isInitialized => _isInitialized;
  bool get isThinking => _isThinking;

  // Piece values for evaluation
  int _getPieceValue(chess_lib.PieceType type) {
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

  // Piece-square tables for positional evaluation
  static const List<List<int>> _pawnTable = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [50, 50, 50, 50, 50, 50, 50, 50],
    [10, 10, 20, 30, 30, 20, 10, 10],
    [5, 5, 10, 25, 25, 10, 5, 5],
    [0, 0, 0, 20, 20, 0, 0, 0],
    [5, -5, -10, 0, 0, -10, -5, 5],
    [5, 10, 10, -20, -20, 10, 10, 5],
    [0, 0, 0, 0, 0, 0, 0, 0]
  ];

  static const List<List<int>> _knightTable = [
    [-50, -40, -30, -30, -30, -30, -40, -50],
    [-40, -20, 0, 0, 0, 0, -20, -40],
    [-30, 0, 10, 15, 15, 10, 0, -30],
    [-30, 5, 15, 20, 20, 15, 5, -30],
    [-30, 0, 15, 20, 20, 15, 0, -30],
    [-30, 5, 10, 15, 15, 10, 5, -30],
    [-40, -20, 0, 5, 5, 0, -20, -40],
    [-50, -40, -30, -30, -30, -30, -40, -50]
  ];

  static const List<List<int>> _bishopTable = [
    [-20, -10, -10, -10, -10, -10, -10, -20],
    [-10, 0, 0, 0, 0, 0, 0, -10],
    [-10, 0, 5, 10, 10, 5, 0, -10],
    [-10, 5, 5, 10, 10, 5, 5, -10],
    [-10, 0, 10, 10, 10, 10, 0, -10],
    [-10, 10, 10, 10, 10, 10, 10, -10],
    [-10, 5, 0, 0, 0, 0, 5, -10],
    [-20, -10, -10, -10, -10, -10, -10, -20]
  ];

  static const List<List<int>> _rookTable = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [5, 10, 10, 10, 10, 10, 10, 5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [0, 0, 0, 5, 5, 0, 0, 0]
  ];

  static const List<List<int>> _queenTable = [
    [-20, -10, -10, -5, -5, -10, -10, -20],
    [-10, 0, 0, 0, 0, 0, 0, -10],
    [-10, 0, 5, 5, 5, 5, 0, -10],
    [-5, 0, 5, 5, 5, 5, 0, -5],
    [0, 0, 5, 5, 5, 5, 0, -5],
    [-10, 5, 5, 5, 5, 5, 0, -10],
    [-10, 0, 5, 0, 0, 0, 0, -10],
    [-20, -10, -10, -5, -5, -10, -10, -20]
  ];

  static const List<List<int>> _kingMiddleGameTable = [
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-20, -30, -30, -40, -40, -30, -30, -20],
    [-10, -20, -20, -20, -20, -20, -20, -10],
    [20, 20, 0, 0, 0, 0, 20, 20],
    [20, 30, 10, 0, 0, 10, 30, 20]
  ];

  Future<void> initialize() async {
    _isInitialized = true;
  }

  Future<String> getBestMove(String fen, BotDifficulty difficulty) async {
    if (_isThinking) {
      throw Exception('Bot is already thinking');
    }

    _isThinking = true;

    try {
      // Add small delay for UX
      await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));

      final chess = chess_lib.Chess.fromFEN(fen);
      final moves = chess.generate_moves();

      debugPrint('[BotService] FEN: $fen');
      debugPrint('[BotService] Turn: ${chess.turn}');
      debugPrint('[BotService] Generated ${moves.length} moves');
      if (moves.isNotEmpty) {
        debugPrint('[BotService] First 5 moves: ${moves.take(5).map((m) => _moveToUci(m)).toList()}');
      }

      if (moves.isEmpty) {
        throw Exception('No legal moves available');
      }

      // Chance to make a random move based on difficulty
      if (_random.nextDouble() < difficulty.randomness) {
        final randomMove = moves[_random.nextInt(moves.length)];
        debugPrint('[BotService] Random move selected: ${_moveToUci(randomMove)}');
        return _moveToUci(randomMove);
      }

      // Find best move using minimax
      String? bestMove;
      int bestValue = -999999;
      final isMaximizing = chess.turn == chess_lib.Color.WHITE;
      debugPrint('[BotService] isMaximizing: $isMaximizing');

      for (final move in moves) {
        chess.move(move);
        final value = _minimax(
          chess,
          difficulty.depth - 1,
          -1000000,
          1000000,
          !isMaximizing,
        );
        chess.undo();

        final adjustedValue = isMaximizing ? value : -value;
        if (adjustedValue > bestValue) {
          bestValue = adjustedValue;
          bestMove = _moveToUci(move);
        }
      }

      return bestMove ?? _moveToUci(moves[0]);
    } finally {
      _isThinking = false;
    }
  }

  int _minimax(chess_lib.Chess chess, int depth, int alpha, int beta, bool isMaximizing) {
    if (depth == 0 || chess.game_over) {
      return _evaluateBoard(chess);
    }

    final moves = chess.generate_moves();

    if (isMaximizing) {
      int maxEval = -999999;
      for (final move in moves) {
        chess.move(move);
        final eval = _minimax(chess, depth - 1, alpha, beta, false);
        chess.undo();
        maxEval = max(maxEval, eval);
        alpha = max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      int minEval = 999999;
      for (final move in moves) {
        chess.move(move);
        final eval = _minimax(chess, depth - 1, alpha, beta, true);
        chess.undo();
        minEval = min(minEval, eval);
        beta = min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  int _evaluateBoard(chess_lib.Chess chess) {
    if (chess.in_checkmate) {
      return chess.turn == chess_lib.Color.WHITE ? -100000 : 100000;
    }
    if (chess.in_stalemate || chess.in_draw) {
      return 0;
    }

    int score = 0;

    // Evaluate material and position
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = chess.board[row * 16 + col];
        if (piece != null) {
          final pieceValue = _getPieceValue(piece.type);
          final positionValue = _getPositionValue(piece, row, col);

          if (piece.color == chess_lib.Color.WHITE) {
            score += pieceValue + positionValue;
          } else {
            score -= pieceValue + positionValue;
          }
        }
      }
    }

    // Bonus for mobility
    final mobilityBonus = chess.generate_moves().length * 5;
    if (chess.turn == chess_lib.Color.WHITE) {
      score += mobilityBonus;
    } else {
      score -= mobilityBonus;
    }

    return score;
  }

  int _getPositionValue(chess_lib.Piece piece, int row, int col) {
    // Flip row for black pieces
    final adjustedRow = piece.color == chess_lib.Color.WHITE ? row : 7 - row;

    switch (piece.type) {
      case chess_lib.PieceType.PAWN:
        return _pawnTable[adjustedRow][col];
      case chess_lib.PieceType.KNIGHT:
        return _knightTable[adjustedRow][col];
      case chess_lib.PieceType.BISHOP:
        return _bishopTable[adjustedRow][col];
      case chess_lib.PieceType.ROOK:
        return _rookTable[adjustedRow][col];
      case chess_lib.PieceType.QUEEN:
        return _queenTable[adjustedRow][col];
      case chess_lib.PieceType.KING:
        return _kingMiddleGameTable[adjustedRow][col];
      default:
        return 0;
    }
  }

  String _moveToUci(chess_lib.Move move) {
    // Use the chess package's built-in algebraic notation
    final from = move.fromAlgebraic;
    final to = move.toAlgebraic;
    final promotion = move.promotion != null ? move.promotion!.name.toLowerCase() : '';
    return '$from$to$promotion';
  }

  void stopThinking() {
    // No-op for pure Dart implementation
  }

  void dispose() {
    _isInitialized = false;
  }
}
