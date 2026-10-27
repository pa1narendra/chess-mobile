import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Hint system (chess.com model — 2 stages): 0=none, 1=piece highlighted, 2=move revealed
  int _hintLevel = 0;
  String? _hintText;

  // Square highlight overlays passed to the board (square -> color)
  Map<String, ui.Color> _highlights = {};

  // Track puzzles already seen so we don't repeat them — scoped per user
  final Set<String> _seenPuzzleIds = {};
  String _userId = 'guest';

  // Per-user SharedPreferences keys
  String get _seenIdsKey => 'puzzle_seen_ids_$_userId';
  String get _dailyDoneKey => 'daily_puzzle_done_date_$_userId';

  @override
  void initState() {
    super.initState();
    _init();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _init() async {
    _loadProgress();

    // Resolve the current user so puzzle progress is tracked per-account.
    // A different user on the same device gets their own daily puzzle.
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _userId = (auth.user?['_id'] ?? auth.user?['id'] ?? 'guest').toString();

    final prefs = await SharedPreferences.getInstance();
    _seenPuzzleIds.addAll(prefs.getStringList(_seenIdsKey) ?? []);

    // If THIS user already finished today's daily, open a fresh random puzzle
    final dailyAlreadyDone = prefs.getString(_dailyDoneKey) == _todayKey();
    _loadPuzzle(daily: !dailyAlreadyDone);
  }

  /// Persists that the current puzzle was completed (solved or solution shown)
  /// so it isn't served again. Scoped to the current user.
  Future<void> _markPuzzleCompleted() async {
    final id = _puzzleData?['puzzle']?['id'] as String?;
    final prefs = await SharedPreferences.getInstance();

    if (id != null) {
      _seenPuzzleIds.add(id);
      // Cap the stored history at 200 most-recent IDs
      var list = _seenPuzzleIds.toList();
      if (list.length > 200) list = list.sublist(list.length - 200);
      _seenPuzzleIds
        ..clear()
        ..addAll(list);
      await prefs.setStringList(_seenIdsKey, list);
    }
    if (_isDaily) {
      await prefs.setString(_dailyDoneKey, _todayKey());
    }
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
      _recordedFailureForThisPuzzle = false;
      _processingMove = false;
      _hintLevel = 0;
      _hintText = null;
      _highlights = {};
      _status = 'Loading...';
    });

    try {
      Map<String, dynamic> data;
      // For random puzzles, retry a few times to avoid serving an already-seen puzzle
      int attempt = 0;
      while (true) {
        final result = daily
            ? await ApiService.getDailyPuzzle()
            : await ApiService.getRandomPuzzle();
        data = result['data'] as Map<String, dynamic>;
        final id = data['puzzle']?['id'] as String?;
        attempt++;
        if (daily || id == null || !_seenPuzzleIds.contains(id) || attempt >= 4) {
          break;
        }
        debugPrint('[Puzzle] Skipping already-seen puzzle $id, retrying...');
      }

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

  bool _recordedFailureForThisPuzzle = false;
  bool _processingMove = false; // guards against re-entrancy during snap-back

  // Chess.com-style highlight colors
  static const _hintColor = ui.Color.fromARGB(130, 255, 196, 0);    // translucent amber
  static const _correctColor = ui.Color.fromARGB(120, 76, 175, 80); // translucent green
  static const _wrongColor = ui.Color.fromARGB(140, 244, 67, 54);   // translucent red

  void _onMove() {
    if (_puzzleComplete || _chess == null || _processingMove) return;

    final controllerGame = _boardController.game;
    final history = controllerGame.history;
    if (history.isEmpty) return;

    final lastMove = history.last.move;
    final from = lastMove.fromAlgebraic;
    final to = lastMove.toAlgebraic;
    final userMove = '$from$to${lastMove.promotion?.name ?? ''}';
    final expected = _solution[_solutionIndex];

    debugPrint('[Puzzle] User played: $userMove, expected: $expected, '
        'index: $_solutionIndex/${_solution.length}');

    final stripPromo = (String m) => m.length > 4 ? m.substring(0, 4) : m;
    final isCorrect = userMove == expected || stripPromo(userMove) == stripPromo(expected);

    if (isCorrect) {
      _solutionIndex++;
      _hintText = null;
      _hintLevel = 0;

      // Green flash on the move just played
      setState(() {
        _highlights = {from: _correctColor, to: _correctColor};
        _status = 'Best move!';
      });

      if (_solutionIndex >= _solution.length) {
        setState(() {
          _puzzleComplete = true;
          _status = 'Puzzle solved!';
        });
        _markPuzzleCompleted();
        if (!_showedSolution && !_recordedFailureForThisPuzzle) {
          _recordResult(true);
        }
        return;
      }

      // Auto-play opponent's reply after a short delay
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted || _chess == null || _solutionIndex >= _solution.length) return;
        final oppMove = _solution[_solutionIndex];
        final of = oppMove.substring(0, 2);
        final ot = oppMove.substring(2, 4);
        final op = oppMove.length > 4 ? oppMove[4] : null;

        if (op != null) {
          _boardController.makeMoveWithPromotion(from: of, to: ot, pieceToPromoteTo: op);
        } else {
          _boardController.makeMove(from: of, to: ot);
        }

        setState(() {
          _solutionIndex++;
          _highlights = {of: _correctColor, ot: _correctColor};
          _status = 'Your turn';
        });
      });
    } else {
      // WRONG — chess.com behavior: briefly show the move, flash red, then snap back
      _processingMove = true;
      setState(() {
        _highlights = {to: _wrongColor};
        _status = 'Incorrect — try again';
      });

      if (!_recordedFailureForThisPuzzle) {
        _recordedFailureForThisPuzzle = true;
        _recordResult(false);
      }

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _resetToCorrectPosition();
        setState(() {
          _highlights = {};
          _processingMove = false;
        });
      });
    }
  }

  /// Rebuilds the board to the correct state: puzzle start FEN + all correctly
  /// played solution moves so far. Reliable across captures/promotions.
  void _resetToCorrectPosition() {
    final puzzleFen = _puzzleData?['puzzle']?['fen'] as String?;
    if (puzzleFen == null) return;

    _boardController.loadFen(puzzleFen);
    for (int i = 0; i < _solutionIndex; i++) {
      final move = _solution[i];
      final f = move.substring(0, 2);
      final t = move.substring(2, 4);
      final p = move.length > 4 ? move[4] : null;
      if (p != null) {
        _boardController.makeMoveWithPromotion(from: f, to: t, pieceToPromoteTo: p);
      } else {
        _boardController.makeMove(from: f, to: t);
      }
    }
  }

  /// 2-stage hint (chess.com model):
  ///  - Stage 1: highlight the piece to move (from-square, amber)
  ///  - Stage 2: highlight the full move (from + to, amber)
  void _requestHint() {
    if (_solutionIndex >= _solution.length) return;
    final move = _solution[_solutionIndex];
    final from = move.substring(0, 2);
    final to = move.substring(2, 4);

    setState(() {
      if (_hintLevel < 2) _hintLevel++;
      if (_hintLevel == 1) {
        final piece = _chess?.get(from);
        final pieceName = _pieceName(piece?.type.toString());
        _hintText = 'Move your $pieceName';
        _highlights = {from: _hintColor};
      } else {
        _hintText = '${from.toUpperCase()} → ${to.toUpperCase()}';
        _highlights = {from: _hintColor, to: _hintColor};
      }
    });
  }

  String _pieceName(String? type) {
    switch (type?.toLowerCase()) {
      case 'p': return 'pawn';
      case 'n': return 'knight';
      case 'b': return 'bishop';
      case 'r': return 'rook';
      case 'q': return 'queen';
      case 'k': return 'king';
      default: return 'piece';
    }
  }

  Future<void> _showSolution() async {
    if (_puzzleData == null) return;
    final puzzleFen = _puzzleData!['puzzle']?['fen'] as String?;
    if (puzzleFen == null) return;

    setState(() {
      _showedSolution = true;
      _highlights = {};
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
      // Highlight each solution move as it's played (user moves green, opponent amber)
      final isUserMove = i % 2 == 0;
      setState(() {
        _highlights = {
          from: isUserMove ? _correctColor : _hintColor,
          to: isUserMove ? _correctColor : _hintColor,
        };
      });
      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (mounted) {
      setState(() {
        _puzzleComplete = true;
        _highlights = {};
        _status = 'Solution shown';
      });
      _markPuzzleCompleted();
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
    if (_status == 'Best move!' || _status == 'Puzzle solved!') statusColor = AppColors.emeraldGreen;
    if (_status.startsWith('Incorrect')) statusColor = AppColors.roseError;
    if (_status == 'Showing solution...' || _status == 'Solution shown') statusColor = AppColors.amberWarning;

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

        // Status banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: statusColor.withValues(alpha: 0.1),
          child: Text(
            _puzzleComplete
                ? _status
                : '${_userColor == PlayerColor.white ? "White" : "Black"} to play — $_status',
            style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),

        // Hint banner
        if (_hintText != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.electricBlue.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: AppColors.electricBlue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hintText!,
                    style: const TextStyle(color: AppColors.electricBlue, fontSize: 13, fontWeight: FontWeight.w600),
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
              enableUserMoves: !_puzzleComplete && !_processingMove,
              boardOrientation: _userColor,
              onMove: _onMove,
              highlightSquares: _highlights,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hint + Solution row (chess.com model: hint is 2-stage, solution always available)
              if (!_puzzleComplete && !_showedSolution)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _hintLevel >= 2 ? null : _requestHint,
                          icon: Icon(Icons.lightbulb_outline_rounded,
                              color: _hintLevel >= 2 ? AppColors.textMuted : AppColors.electricBlue),
                          label: Text(
                            _hintLevel == 0 ? 'Hint' : _hintLevel == 1 ? 'Reveal move' : 'Move shown',
                            style: TextStyle(
                                color: _hintLevel >= 2 ? AppColors.textMuted : AppColors.electricBlue),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.electricBlue.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showSolution,
                          icon: const Icon(Icons.visibility_outlined, color: AppColors.amberWarning),
                          label: const Text('Solution', style: TextStyle(color: AppColors.amberWarning)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.amberWarning.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _loadPuzzle(daily: false),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('New Puzzle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tealAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
      },
    );
  }
}
