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
      if (mounted) setState(() => _progress = result['data']);
    } catch (e) {
      debugPrint('[Puzzles] Failed to load progress: $e');
    }
  }

  Future<void> _loadPuzzle({bool daily = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _puzzleComplete = false;
      _showedSolution = false;
      _solutionIndex = 0;
      _lastMoveWasWrong = false;
      _recordedFailureForThisPuzzle = false;
      _status = 'Loading...';
    });

    try {
      final result = daily
          ? await ApiService.getDailyPuzzle()
          : await ApiService.getRandomPuzzle();
      final data = result['data'] as Map<String, dynamic>;

      // Lichess provides the puzzle FEN directly — use it instead of replaying PGN
      // (some PGNs have ambiguous SAN that the Dart chess package can't parse)
      final puzzle = data['puzzle'] as Map<String, dynamic>?;
      if (puzzle == null) throw Exception('Invalid puzzle data');

      final puzzleFen = puzzle['fen'] as String?;
      if (puzzleFen == null || puzzleFen.isEmpty) {
        throw Exception('Puzzle FEN missing');
      }

      final solution = (puzzle['solution'] as List?)?.cast<String>() ?? [];
      if (solution.isEmpty) throw Exception('No solution provided');

      // Build local chess instance from FEN
      final chess = chess_lib.Chess.fromFEN(puzzleFen);

      // Determine user color from FEN turn indicator
      final fenParts = puzzleFen.split(' ');
      final turnChar = fenParts.length > 1 ? fenParts[1] : 'w';
      final userColor = turnChar == 'w' ? PlayerColor.white : PlayerColor.black;

      debugPrint('[Puzzle] Loaded — turn=$turnChar, solution[0]=${solution[0]}, fen=$puzzleFen');

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

      _boardController.loadFen(puzzleFen);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Tracks whether the user's CURRENT pending move was correct so we can show feedback
  // and let them undo without instantly punishing them.
  bool _lastMoveWasWrong = false;
  bool _recordedFailureForThisPuzzle = false;

  void _onMove() {
    if (_puzzleComplete || _chess == null) return;

    final controllerGame = _boardController.game;
    final history = controllerGame.history;
    if (history.isEmpty) return;

    final lastMove = history.last.move;
    final userMove = '${lastMove.fromAlgebraic}${lastMove.toAlgebraic}${lastMove.promotion?.name ?? ''}';

    final expected = _solution[_solutionIndex];

    debugPrint('[Puzzle] User played: $userMove, expected: $expected, '
        'solutionIndex: $_solutionIndex/${_solution.length}');

    final stripPromo = (String m) => m.length > 4 ? m.substring(0, 4) : m;
    final isCorrect = userMove == expected ||
        stripPromo(userMove) == stripPromo(expected);

    if (isCorrect) {
      _solutionIndex++;
      _lastMoveWasWrong = false;

      if (_solutionIndex >= _solution.length) {
        setState(() {
          _puzzleComplete = true;
          _status = 'Solved!';
        });
        // Only record as success if user never showed the solution AND never recorded a failure
        if (!_showedSolution && !_recordedFailureForThisPuzzle) {
          _recordResult(true);
        }
        return;
      }

      setState(() => _status = 'Correct!');

      // Play opponent's response after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _chess == null || _solutionIndex >= _solution.length) return;
        final oppMove = _solution[_solutionIndex];
        final from = oppMove.substring(0, 2);
        final to = oppMove.substring(2, 4);
        final promotion = oppMove.length > 4 ? oppMove[4] : null;

        if (promotion != null) {
          _boardController.makeMoveWithPromotion(from: from, to: to, pieceToPromoteTo: promotion);
        } else {
          _boardController.makeMove(from: from, to: to);
        }

        setState(() {
          _solutionIndex++;
          _status = 'Your turn';
        });
      });
    } else {
      // Wrong move — DO NOT undo. Let them keep exploring, show soft feedback.
      setState(() {
        _status = "Not the puzzle's move — Undo to try again";
        _lastMoveWasWrong = true;
      });
      // Record failure once per puzzle so rating isn't double-penalized
      if (!_recordedFailureForThisPuzzle) {
        _recordedFailureForThisPuzzle = true;
        _recordResult(false);
      }
    }
  }

  void _undoLastMove() {
    if (_chess == null) return;
    _boardController.undoMove();
    setState(() {
      _lastMoveWasWrong = false;
      _status = 'Your turn';
    });
  }

  Future<void> _showSolution() async {
    if (_puzzleData == null) return;
    final puzzleFen = _puzzleData!['puzzle']?['fen'] as String?;
    if (puzzleFen == null) return;

    setState(() {
      _showedSolution = true;
      _lastMoveWasWrong = false;
      _status = 'Showing solution...';
    });
    if (!_recordedFailureForThisPuzzle) {
      _recordedFailureForThisPuzzle = true;
      _recordResult(false);
    }

    // Reset to puzzle starting position, then animate each solution move
    _boardController.loadFen(puzzleFen);
    await Future.delayed(const Duration(milliseconds: 600));

    for (int i = 0; i < _solution.length; i++) {
      if (!mounted) return;
      final move = _solution[i];
      final from = move.substring(0, 2);
      final to = move.substring(2, 4);
      final promotion = move.length > 4 ? move[4] : null;

      if (promotion != null) {
        _boardController.makeMoveWithPromotion(from: from, to: to, pieceToPromoteTo: promotion);
      } else {
        _boardController.makeMove(from: from, to: to);
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (mounted) {
      setState(() {
        _puzzleComplete = true;
        _status = 'Solution shown';
      });
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
    } catch (e) {
      debugPrint('[Puzzles] Failed to record result: $e');
    }
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
    if (_lastMoveWasWrong) statusColor = AppColors.amberWarning;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve ~220px for top info bar (60) + status (40) + themes (40) + actions (80)
        final maxBoardSize = (constraints.maxHeight - 220).clamp(200.0, constraints.maxWidth);

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

        // Status banner — softer styling, with Undo button when wrong move was made
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: statusColor.withValues(alpha: 0.1),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _puzzleComplete
                      ? 'Puzzle Solved!'
                      : '${_userColor == PlayerColor.white ? "White" : "Black"} to play — $_status',
                  style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w600),
                  textAlign: _lastMoveWasWrong ? TextAlign.start : TextAlign.center,
                ),
              ),
              if (_lastMoveWasWrong)
                TextButton.icon(
                  onPressed: _undoLastMove,
                  icon: const Icon(Icons.undo_rounded, size: 16, color: AppColors.tealAccent),
                  label: const Text('Undo', style: TextStyle(color: AppColors.tealAccent, fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
        ),

        // Board — constrained so it doesn't push other elements off-screen
        Center(
          child: SizedBox(
            width: maxBoardSize,
            height: maxBoardSize,
            child: CustomChessBoard(
              controller: _boardController,
              enableUserMoves: !_puzzleComplete,
              boardOrientation: _userColor,
              onMove: _onMove,
            ),
          ),
        ),

        // Themes
        if (themes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: themes.take(4).map((theme) => Container(
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
                    onPressed: _showSolution,
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
      },
    );
  }
}
