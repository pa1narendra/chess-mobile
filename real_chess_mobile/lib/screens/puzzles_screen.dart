import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../api/api_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_chess_board.dart';
import '../main.dart';

class PuzzlesScreen extends StatefulWidget {
  const PuzzlesScreen({super.key});

  @override
  State<PuzzlesScreen> createState() => _PuzzlesScreenState();
}

class _PuzzlesScreenState extends State<PuzzlesScreen> {
  final ChessBoardController _boardController = ChessBoardController();

  Map<String, dynamic>? _puzzleData;
  Map<String, dynamic>? _progress;
  bool _isLoading = true;
  String? _error;
  bool _isDaily = false;

  // Puzzle state
  chess_lib.Chess? _chess;
  List<String> _solution = []; // UCI moves
  int _solutionIndex = 0;
  PlayerColor _userColor = PlayerColor.white;
  String _status = 'Your turn'; // 'Your turn' | 'Correct!' | 'Wrong' | 'Solved!'
  bool _puzzleComplete = false;
  bool _showedSolution = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _loadPuzzle(daily: true);
  }

  Future<void> _loadProgress() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    try {
      final result = await ApiService.getPuzzleProgress(token);
      setState(() => _progress = result['data']);
    } catch (_) {}
  }

  Future<void> _loadPuzzle({bool daily = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _puzzleComplete = false;
      _showedSolution = false;
      _solutionIndex = 0;
      _status = 'Loading...';
    });

    try {
      final result = daily
          ? await ApiService.getDailyPuzzle()
          : await ApiService.getRandomPuzzle();
      final data = result['data'] as Map<String, dynamic>;

      // Lichess puzzle format:
      // { game: { pgn: "e4 e5 ..." }, puzzle: { initialPly, solution: [uci...], rating, themes } }
      final pgn = data['game']?['pgn'] as String?;
      final puzzle = data['puzzle'] as Map<String, dynamic>?;
      if (pgn == null || puzzle == null) throw Exception('Invalid puzzle data');

      final initialPly = (puzzle['initialPly'] as num?)?.toInt() ?? 0;
      final solution = (puzzle['solution'] as List?)?.cast<String>() ?? [];

      // Replay game up to initialPly
      final chess = chess_lib.Chess();
      final moves = pgn.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

      // Apply moves up to and INCLUDING initialPly (the last move before puzzle starts)
      // Lichess convention: after applying initialPly+1 moves, it's the puzzle solver's turn
      for (int i = 0; i <= initialPly && i < moves.length; i++) {
        final san = moves[i];
        chess.move(san);
      }

      // Whose turn it is now = user's color
      final userColor = chess.turn == chess_lib.Color.WHITE ? PlayerColor.white : PlayerColor.black;

      setState(() {
        _puzzleData = data;
        _chess = chess;
        _solution = solution;
        _solutionIndex = 0;
        _userColor = userColor;
        _status = 'Your turn';
        _isDaily = daily;
        _isLoading = false;
      });

      _boardController.loadFen(chess.fen);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onMove() {
    if (_puzzleComplete || _chess == null) return;

    // Get the last move from the controller
    final controllerGame = _boardController.game;
    final history = controllerGame.history;
    if (history.isEmpty) return;

    // Compare against expected solution move
    final expected = _solution[_solutionIndex];

    // Get the user's move in UCI format
    // The chess package history stores State objects with move details
    // We need to check what move was made by comparing FENs or using the controller's last move
    // Simpler: use controllerGame.san_moves().last to get SAN, but we need UCI.
    // chess.js stores move objects with from/to/promotion.

    // Get the actual move made
    final lastMoveMap = controllerGame.undo_move();
    if (lastMoveMap == null) return;
    // Re-apply the move
    controllerGame.move(lastMoveMap);

    final userMove = '${lastMoveMap.fromAlgebraic}${lastMoveMap.toAlgebraic}${lastMoveMap.promotion?.name ?? ''}';

    if (userMove == expected || userMove.replaceAll(RegExp(r'[qrbn]$'), '') == expected.replaceAll(RegExp(r'[qrbn]$'), '')) {
      // Correct!
      _solutionIndex++;
      _status = 'Correct!';

      if (_solutionIndex >= _solution.length) {
        // Puzzle solved!
        setState(() {
          _puzzleComplete = true;
          _status = 'Solved!';
        });
        _recordResult(true);
        return;
      }

      // Play the opponent's response automatically after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _chess == null) return;
        final oppMove = _solution[_solutionIndex];
        final from = oppMove.substring(0, 2);
        final to = oppMove.substring(2, 4);
        final promotion = oppMove.length > 4 ? oppMove[4] : null;

        _boardController.makeMove(from: from, to: to);
        if (promotion != null) {
          // For promotion, use makeMoveWithPromotion
          _boardController.makeMoveWithPromotion(from: from, to: to, pieceToPromoteTo: promotion);
        }

        setState(() {
          _solutionIndex++;
          _status = 'Your turn';
        });
      });
    } else {
      // Wrong move - undo it and show feedback
      _boardController.undoMove();
      setState(() {
        _status = 'Wrong move, try again';
        _showedSolution = true;
      });
      _recordResult(false);
    }
  }

  Future<void> _recordResult(bool success) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    final puzzleRating = (_puzzleData?['puzzle']?['rating'] as num?)?.toInt();
    try {
      final result = await ApiService.recordPuzzleResult(token, success: success, puzzleRating: puzzleRating);
      final newRating = result['data']?['newRating'];
      if (newRating != null && mounted) {
        setState(() {
          _progress = {...?_progress, 'puzzleRating': newRating};
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Puzzles', style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.extension_rounded, color: AppColors.tealAccent, size: 14),
                      const SizedBox(width: 4),
                      Text('${_progress!['puzzleRating'] ?? 1200}', style: const TextStyle(color: AppColors.tealAccent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.roseError, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: () => _loadPuzzle(daily: _isDaily), child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final puzzle = _puzzleData?['puzzle'] as Map<String, dynamic>?;
    final rating = puzzle?['rating'] ?? 1500;
    final themes = (puzzle?['themes'] as List?)?.cast<String>() ?? [];

    Color statusColor = AppColors.textSecondary;
    if (_status == 'Correct!') statusColor = AppColors.emeraldGreen;
    if (_status == 'Solved!') statusColor = AppColors.tealAccent;
    if (_status.startsWith('Wrong')) statusColor = AppColors.roseError;

    return Column(
      children: [
        // Info bar
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.surfaceDark,
          child: Row(
            children: [
              Icon(_isDaily ? Icons.calendar_today_rounded : Icons.shuffle_rounded, color: AppColors.tealAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                _isDaily ? 'Daily Puzzle' : 'Random Puzzle',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.amberWarning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$rating', style: const TextStyle(color: AppColors.amberWarning, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),

        // Status banner
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          color: statusColor.withValues(alpha: 0.1),
          child: Center(
            child: Text(
              _puzzleComplete
                  ? 'Puzzle Solved! ${_userColor == PlayerColor.white ? "Find the win for White" : "Find the win for Black"}'
                  : '${_userColor == PlayerColor.white ? "White" : "Black"} to play — $_status',
              style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        // Board
        Padding(
          padding: const EdgeInsets.all(4),
          child: CustomChessBoard(
            controller: _boardController,
            enableUserMoves: !_puzzleComplete,
            boardOrientation: _userColor,
            onMove: _onMove,
          ),
        ),

        // Themes
        if (themes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: themes.take(5).map((theme) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(theme, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              )).toList(),
            ),
          ),

        const Spacer(),

        // Actions
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _loadPuzzle(daily: false),
                  icon: const Icon(Icons.shuffle_rounded, color: AppColors.textPrimary),
                  label: const Text('New Puzzle', style: TextStyle(color: AppColors.textPrimary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (!_puzzleComplete && !_showedSolution) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showedSolution = true;
                        _status = 'Showed solution';
                      });
                      _recordResult(false);
                    },
                    icon: const Icon(Icons.visibility_outlined, color: AppColors.amberWarning),
                    label: const Text('Show Solution', style: TextStyle(color: AppColors.amberWarning)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.amberWarning.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
