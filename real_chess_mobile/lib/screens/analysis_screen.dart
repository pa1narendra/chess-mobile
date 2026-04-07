import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../api/api_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_chess_board.dart';
import '../main.dart';

class AnalysisScreen extends StatefulWidget {
  final String gameId;
  const AnalysisScreen({super.key, required this.gameId});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final ChessBoardController _boardController = ChessBoardController();
  Map<String, dynamic>? _game;
  List<Map<String, dynamic>> _evaluations = [];
  List<String> _fens = [];
  List<String> _sans = [];
  int _currentMoveIndex = 0;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _hasAnalysis = false;
  String? _error;
  Map<String, dynamic>? _accuracy;

  String _whiteName = 'White';
  String _blackName = 'Black';

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  Future<void> _loadGame() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final result = await ApiService.getGameDetails(widget.gameId);
      final game = result['data'] as Map<String, dynamic>;

      // Replay moves to build FEN + SAN lists
      final moves = (game['moves'] as List?)?.cast<String>() ?? [];
      final chess = chess_lib.Chess();
      final fens = <String>[chess.fen];
      final sans = <String>[];

      for (final uci in moves) {
        if (uci.length < 4) continue;
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        final promotion = uci.length > 4 ? uci[4] : null;
        final moveResult = chess.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
        if (moveResult) {
          fens.add(chess.fen);
          final sanList = chess.san_moves();
          sans.add(sanList.isNotEmpty && sanList.last != null ? sanList.last! : uci);
        }
      }

      // Check for existing analysis
      final analysis = game['analysis'];
      final hasAnalysis = analysis != null && analysis['evaluated'] == true;

      setState(() {
        _game = game;
        _fens = fens;
        _sans = sans;
        _whiteName = game['whiteName'] ?? 'White';
        _blackName = game['blackName'] ?? 'Black';
        _hasAnalysis = hasAnalysis;
        if (hasAnalysis) {
          _accuracy = analysis['accuracy'] as Map<String, dynamic>?;
          _evaluations = _parseEvaluations(analysis);
        }
        _currentMoveIndex = fens.length - 1;
        _isLoading = false;
      });

      _boardController.loadFen(_fens[_currentMoveIndex]);
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> _parseEvaluations(Map<String, dynamic> analysis) {
    final evals = (analysis['evaluations'] ?? analysis['keyMoments'] ?? []) as List;
    return evals.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _runAnalysis() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final result = await ApiService.analyzeGame(widget.gameId, token);
      final analysis = result['analysis'] as Map<String, dynamic>?;
      if (analysis != null) {
        setState(() {
          _hasAnalysis = true;
          _accuracy = analysis['accuracy'] as Map<String, dynamic>?;
          _evaluations = _parseEvaluations(analysis);
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: AppColors.roseError),
        );
      }
    }
  }

  void _goToMove(int index) {
    if (index < 0 || index >= _fens.length) return;
    setState(() => _currentMoveIndex = index);
    _boardController.loadFen(_fens[index]);
  }

  // Get evaluation for the current move index
  double? _getEvalAtIndex(int index) {
    if (!_hasAnalysis || _evaluations.isEmpty) return null;
    for (final ev in _evaluations) {
      if (ev['moveIndex'] == index) return (ev['evaluation'] as num?)?.toDouble();
    }
    return null;
  }

  String? _getClassificationAtIndex(int index) {
    if (!_hasAnalysis || _evaluations.isEmpty) return null;
    for (final ev in _evaluations) {
      if (ev['moveIndex'] == index) return ev['classification'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Analysis', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (!_hasAnalysis && !_isLoading)
            TextButton.icon(
              onPressed: _isAnalyzing ? null : _runAnalysis,
              icon: _isAnalyzing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.tealAccent))
                  : const Icon(Icons.analytics_outlined, color: AppColors.tealAccent, size: 20),
              label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze', style: const TextStyle(color: AppColors.tealAccent)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.roseError)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Accuracy summary bar (if analyzed)
        if (_hasAnalysis && _accuracy != null) _buildAccuracyBar(),

        // Opponent player bar
        _buildCompactPlayerBar(_whiteName == _blackName ? _blackName : _whiteName == 'White' ? _blackName : _whiteName, false),

        // Eval bar + Board
        _buildEvalBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CustomChessBoard(
            controller: _boardController,
            enableUserMoves: false,
            boardOrientation: PlayerColor.white,
          ),
        ),

        // Current player bar
        _buildCompactPlayerBar(_whiteName, true),

        // Navigation controls
        _buildNavControls(),

        // Move list
        Expanded(child: _buildMoveList()),
      ],
    );
  }

  Widget _buildAccuracyBar() {
    final wAcc = _accuracy?['w'] ?? 0;
    final bAcc = _accuracy?['b'] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surfaceDark,
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          Text('$wAcc%', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          const Text('Accuracy', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          Text('$bAcc%', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 6),
          Icon(Icons.circle, color: Colors.grey[800], size: 10),
        ],
      ),
    );
  }

  Widget _buildEvalBar() {
    if (!_hasAnalysis) return const SizedBox.shrink();

    final eval = _getEvalAtIndex(_currentMoveIndex);
    // Convert centipawns to visual fraction using sigmoid
    double whiteFraction = 0.5;
    String evalText = '0.0';
    if (eval != null) {
      whiteFraction = 1.0 / (1.0 + exp(-eval / 400.0));
      whiteFraction = whiteFraction.clamp(0.05, 0.95);
      if (eval.abs() >= 10000) {
        evalText = eval > 0 ? 'M' : '-M';
      } else {
        evalText = (eval / 100.0).toStringAsFixed(1);
        if (eval > 0) evalText = '+$evalText';
      }
    }

    return Container(
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        children: [
          // Background (black side)
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          // White portion
          FractionallySizedBox(
            widthFactor: whiteFraction,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(4),
                  topRight: whiteFraction >= 0.95 ? const Radius.circular(4) : Radius.zero,
                ),
              ),
            ),
          ),
          // Eval text
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.deepDark.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(evalText, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPlayerBar(String name, bool isBottom) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surfaceDark,
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isBottom ? Colors.white : Colors.grey[800],
              border: Border.all(color: AppColors.textMuted, width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildNavControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.surfaceDark,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: _currentMoveIndex > 0 ? () => _goToMove(0) : null,
            icon: Icon(Icons.skip_previous, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
          ),
          IconButton(
            onPressed: _currentMoveIndex > 0 ? () => _goToMove(_currentMoveIndex - 1) : null,
            icon: Icon(Icons.chevron_left, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
          ),
          Text('${_currentMoveIndex}/${_fens.length - 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          IconButton(
            onPressed: _currentMoveIndex < _fens.length - 1 ? () => _goToMove(_currentMoveIndex + 1) : null,
            icon: Icon(Icons.chevron_right, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
          ),
          IconButton(
            onPressed: _currentMoveIndex < _fens.length - 1 ? () => _goToMove(_fens.length - 1) : null,
            icon: Icon(Icons.skip_next, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveList() {
    if (_sans.isEmpty) {
      return const Center(child: Text('No moves', style: TextStyle(color: AppColors.textMuted)));
    }

    // Build move pairs (1. e4 e5, 2. Nf3 Nc6, etc.)
    final movePairs = <Widget>[];
    for (int i = 0; i < _sans.length; i += 2) {
      final moveNum = (i ~/ 2) + 1;
      final whiteSan = _sans[i];
      final blackSan = i + 1 < _sans.length ? _sans[i + 1] : null;
      final whiteClass = _getClassificationAtIndex(i + 1);
      final blackClass = blackSan != null ? _getClassificationAtIndex(i + 2) : null;

      movePairs.add(_buildMovePairRow(moveNum, whiteSan, blackSan, i + 1, whiteClass, blackClass));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: movePairs,
    );
  }

  Widget _buildMovePairRow(int moveNum, String whiteSan, String? blackSan, int whiteIndex, String? whiteClass, String? blackClass) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Move number
          SizedBox(
            width: 32,
            child: Text('$moveNum.', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          // White's move
          Expanded(
            child: _buildMoveCell(whiteSan, whiteIndex, whiteClass),
          ),
          // Black's move
          Expanded(
            child: blackSan != null
                ? _buildMoveCell(blackSan, whiteIndex + 1, blackClass)
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveCell(String san, int moveIndex, String? classification) {
    final isActive = moveIndex == _currentMoveIndex;
    final classColor = _classificationColor(classification);

    return GestureDetector(
      onTap: () => _goToMove(moveIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? AppColors.tealAccent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isActive ? Border.all(color: AppColors.tealAccent.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                san,
                style: TextStyle(
                  color: isActive ? AppColors.tealAccent : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (classification != null && classColor != null) ...[
              const SizedBox(width: 4),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: classColor, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color? _classificationColor(String? c) {
    switch (c) {
      case 'brilliant': return AppColors.tealAccent;
      case 'great': return AppColors.emeraldGreen;
      case 'good': return null;
      case 'book': return null;
      case 'inaccuracy': return Colors.orange;
      case 'mistake': return AppColors.amberWarning;
      case 'blunder': return AppColors.roseError;
      default: return null;
    }
  }
}
