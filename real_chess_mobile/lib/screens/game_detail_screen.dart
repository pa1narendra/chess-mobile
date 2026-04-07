import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../api/api_service.dart';
import '../widgets/custom_chess_board.dart';
import '../main.dart';
import 'analysis_screen.dart';

class GameDetailScreen extends StatefulWidget {
  final String gameId;
  const GameDetailScreen({super.key, required this.gameId});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  final ChessBoardController _boardController = ChessBoardController();
  Map<String, dynamic>? _game;
  bool _isLoading = true;
  String? _error;

  List<String> _fens = [];
  List<String> _sans = [];
  int _currentMoveIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  Future<void> _loadGame() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final result = await ApiService.getGameDetails(widget.gameId);
      final game = result['data'];

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

      setState(() {
        _game = game;
        _fens = fens;
        _sans = sans;
        _currentMoveIndex = fens.length - 1;
        _isLoading = false;
      });

      _boardController.loadFen(_fens[_currentMoveIndex]);
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _goToMove(int index) {
    if (index < 0 || index >= _fens.length) return;
    setState(() => _currentMoveIndex = index);
    _boardController.loadFen(_fens[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Game ${widget.gameId}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: AppColors.tealAccent),
            tooltip: 'Analyze',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AnalysisScreen(gameId: widget.gameId),
            )),
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
    final whiteName = _game?['whiteName'] ?? 'White';
    final blackName = _game?['blackName'] ?? 'Black';
    final result = _game?['result'];
    final winner = result?['winner'];
    final reason = result?['reason'] ?? '';

    String resultText;
    Color resultColor;
    if (winner == 'w') {
      resultText = '$whiteName wins';
      resultColor = AppColors.emeraldGreen;
    } else if (winner == 'b') {
      resultText = '$blackName wins';
      resultColor = AppColors.emeraldGreen;
    } else {
      resultText = 'Draw';
      resultColor = AppColors.amberWarning;
    }

    return Column(
      children: [
        // Result header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.surfaceDark,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(resultText, style: TextStyle(color: resultColor, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              if (reason.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(child: Text('($reason)', style: TextStyle(color: resultColor.withValues(alpha: 0.7), fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
        ),

        // Board
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CustomChessBoard(
            controller: _boardController,
            enableUserMoves: false,
            boardOrientation: PlayerColor.white,
          ),
        ),

        // Move counter
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _currentMoveIndex == 0
                ? 'Starting position'
                : 'Move ${(_currentMoveIndex + 1) ~/ 2}${_currentMoveIndex % 2 == 1 ? ". " : "... "}${_currentMoveIndex <= _sans.length ? _sans[_currentMoveIndex - 1] : ""}',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),

        // Navigation controls
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          color: AppColors.surfaceDark,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: _currentMoveIndex > 0 ? () => _goToMove(0) : null,
                icon: Icon(Icons.skip_previous, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted),
              ),
              IconButton(
                onPressed: _currentMoveIndex > 0 ? () => _goToMove(_currentMoveIndex - 1) : null,
                icon: Icon(Icons.chevron_left, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted, size: 32),
              ),
              Text('${_currentMoveIndex} / ${_fens.length - 1}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              IconButton(
                onPressed: _currentMoveIndex < _fens.length - 1 ? () => _goToMove(_currentMoveIndex + 1) : null,
                icon: Icon(Icons.chevron_right, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted, size: 32),
              ),
              IconButton(
                onPressed: _currentMoveIndex < _fens.length - 1 ? () => _goToMove(_fens.length - 1) : null,
                icon: Icon(Icons.skip_next, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted),
              ),
            ],
          ),
        ),

        // Move list (horizontal scroll)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sans.length,
              itemBuilder: (context, i) {
                final isActive = i == _currentMoveIndex - 1;
                final moveNum = (i ~/ 2) + 1;
                final isWhite = i % 2 == 0;
                return GestureDetector(
                  onTap: () => _goToMove(i + 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.tealAccent.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${isWhite ? "$moveNum. " : ""}${_sans[i]}',
                      style: TextStyle(
                        color: isActive ? AppColors.tealAccent : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
