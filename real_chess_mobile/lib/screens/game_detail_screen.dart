import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../api/api_service.dart';
import '../main.dart';

class GameDetailScreen extends StatefulWidget {
  final String gameId;

  const GameDetailScreen({super.key, required this.gameId});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  Map<String, dynamic>? _game;
  bool _isLoading = true;
  String? _error;

  // Replay state
  List<String> _fens = [];
  List<String> _sans = [];
  int _currentMoveIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  Future<void> _loadGame() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.getGameDetails(widget.gameId);
      final game = result['data'];

      // Replay moves to build FEN list
      final moves = (game['moves'] as List?)?.cast<String>() ?? [];
      final chess = chess_lib.Chess();
      final fens = <String>[chess.fen];
      final sans = <String>[];

      for (final uci in moves) {
        if (uci.length < 4) continue;
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        final promotion = uci.length > 4 ? uci[4] : null;
        final result = chess.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
        if (result) {
          fens.add(chess.fen);
          // Get the SAN from the last move in history
          final history = chess.history;
          if (history.isNotEmpty) {
            sans.add(history.last.toString());
          }
        }
      }

      setState(() {
        _game = game;
        _fens = fens;
        _sans = sans;
        _currentMoveIndex = fens.length - 1; // Start at final position
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Game ${widget.gameId}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
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
    final accuracy = _game?['analysis']?['accuracy'];

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
          padding: const EdgeInsets.all(16),
          color: AppColors.surfaceDark,
          child: Column(
            children: [
              Text(resultText, style: TextStyle(color: resultColor, fontSize: 18, fontWeight: FontWeight.w700)),
              if (reason.isNotEmpty)
                Text('by $reason', style: TextStyle(color: resultColor.withValues(alpha: 0.7), fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPlayerLabel(whiteName, 'w', winner),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('vs', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  ),
                  _buildPlayerLabel(blackName, 'b', winner),
                ],
              ),
              if (accuracy != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Accuracy: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text('${accuracy['w']}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Text(' - ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text('${accuracy['b']}%', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Board representation (simplified text board)
        Expanded(
          child: Column(
            children: [
              // Move counter
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _currentMoveIndex == 0
                      ? 'Starting position'
                      : 'Move ${(_currentMoveIndex + 1) ~/ 2}${_currentMoveIndex % 2 == 1 ? ". " : "... "}${_currentMoveIndex <= _sans.length ? _sans[_currentMoveIndex - 1] : ""}',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),

              // FEN display
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: _buildTextBoard(_fens[_currentMoveIndex]),
              ),

              const Spacer(),

              // Move navigation controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                color: AppColors.surfaceDark,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: _currentMoveIndex > 0 ? () => setState(() => _currentMoveIndex = 0) : null,
                      icon: Icon(Icons.skip_previous, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted),
                    ),
                    IconButton(
                      onPressed: _currentMoveIndex > 0 ? () => setState(() => _currentMoveIndex--) : null,
                      icon: Icon(Icons.chevron_left, color: _currentMoveIndex > 0 ? AppColors.textPrimary : AppColors.textMuted, size: 32),
                    ),
                    Text(
                      '${_currentMoveIndex} / ${_fens.length - 1}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    IconButton(
                      onPressed: _currentMoveIndex < _fens.length - 1 ? () => setState(() => _currentMoveIndex++) : null,
                      icon: Icon(Icons.chevron_right, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted, size: 32),
                    ),
                    IconButton(
                      onPressed: _currentMoveIndex < _fens.length - 1 ? () => setState(() => _currentMoveIndex = _fens.length - 1) : null,
                      icon: Icon(Icons.skip_next, color: _currentMoveIndex < _fens.length - 1 ? AppColors.textPrimary : AppColors.textMuted),
                    ),
                  ],
                ),
              ),

              // Move list
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sans.length,
                  itemBuilder: (context, i) {
                    final isActive = i == _currentMoveIndex - 1;
                    final moveNum = (i ~/ 2) + 1;
                    final isWhite = i % 2 == 0;
                    return GestureDetector(
                      onTap: () => setState(() => _currentMoveIndex = i + 1),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerLabel(String name, String color, String? winner) {
    final isWinner = winner == color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color: color == 'w' ? Colors.white : Colors.grey[800],
            border: Border.all(color: AppColors.textMuted, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(name, style: TextStyle(
          color: isWinner ? AppColors.emeraldGreen : AppColors.textPrimary,
          fontWeight: isWinner ? FontWeight.w700 : FontWeight.normal,
          fontSize: 15,
        )),
      ],
    );
  }

  Widget _buildTextBoard(String fen) {
    final parts = fen.split(' ');
    final rows = parts[0].split('/');

    const pieceSymbols = {
      'K': '\u2654', 'Q': '\u2655', 'R': '\u2656', 'B': '\u2657', 'N': '\u2658', 'P': '\u2659',
      'k': '\u265A', 'q': '\u265B', 'r': '\u265C', 'b': '\u265D', 'n': '\u265E', 'p': '\u265F',
    };

    return Column(
      children: List.generate(8, (row) {
        final fenRow = rows[row];
        final squares = <Widget>[];
        int col = 0;

        for (final c in fenRow.split('')) {
          if (int.tryParse(c) != null) {
            for (int i = 0; i < int.parse(c); i++) {
              final isLight = (row + col) % 2 == 0;
              squares.add(_buildSquare(null, isLight));
              col++;
            }
          } else {
            final isLight = (row + col) % 2 == 0;
            squares.add(_buildSquare(pieceSymbols[c], isLight));
            col++;
          }
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: squares,
        );
      }),
    );
  }

  Widget _buildSquare(String? piece, bool isLight) {
    final size = (MediaQuery.of(context).size.width - 64) / 8;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFF769656) : const Color(0xFF486A39),
      ),
      child: Center(
        child: piece != null
            ? Text(piece, style: TextStyle(fontSize: size * 0.7))
            : null,
      ),
    );
  }
}
