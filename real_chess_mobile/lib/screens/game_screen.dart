import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../providers/game_provider.dart';
import '../api/socket_service.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Start timer to update display every second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int milliseconds) {
    if (milliseconds < 0) milliseconds = 0;
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              game.leaveGame();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Game in Progress'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  game.leaveGame();
                  Navigator.pop(context);
                },
              ),
              actions: [
                // Connection status indicator
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _buildConnectionIndicator(game.connectionState),
                ),
              ],
            ),
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Error message display
                if (game.errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            game.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => game.clearError(),
                        ),
                      ],
                    ),
                  ),

                // Game status display
                if (game.gameStatus != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      game.gameStatus!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Opponent info with timer (shown at top, so it's the opposite color)
                _buildPlayerBar(
                  context,
                  'Opponent',
                  game.playerColor == 'w' ? game.timeRemaining['b']! : game.timeRemaining['w']!,
                  isCurrentTurn: game.currentTurn != game.playerColor,
                  isOpponent: true,
                ),

                Expanded(
                  child: Center(
                    child: ChessBoard(
                      controller: game.controller,
                      enableUserMoves: game.currentTurn == game.playerColor,
                      boardColor: BoardColor.brown,
                      boardOrientation: game.playerColor == 'w'
                          ? PlayerColor.white
                          : PlayerColor.black,
                      onMove: () {
                        // Get the last move from the controller
                        try {
                          final moveHistory = game.controller.getSan();
                          if (moveHistory != null && moveHistory.isNotEmpty) {
                            // Parse the last move - we need from/to squares
                            // The controller should have made the move already
                            // We'll extract from the game state
                            final gameState = game.controller.game;
                            final history = gameState.history;
                            if (history.isNotEmpty) {
                              final lastMove = history.last;
                              final from = lastMove.move.fromAlgebraic;
                              final to = lastMove.move.toAlgebraic;
                              final promotion = lastMove.move.promotion?.name;
                              game.onUserMove(from, to, promotion: promotion);
                            }
                          }
                        } catch (e) {
                          // ignore: avoid_print
                          print('Error detecting move: $e');
                        }
                      },
                    ),
                  ),
                ),

                // Player info with timer (shown at bottom)
                _buildPlayerBar(
                  context,
                  'You',
                  game.playerColor == 'w' ? game.timeRemaining['w']! : game.timeRemaining['b']!,
                  isCurrentTurn: game.currentTurn == game.playerColor,
                  isOpponent: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerBar(BuildContext context, String name, int timeMs, {required bool isCurrentTurn, required bool isOpponent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? Theme.of(context).primaryColor.withOpacity(0.2)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: isCurrentTurn
            ? Border.all(color: Theme.of(context).primaryColor, width: 2)
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isOpponent ? Icons.person : Icons.person_outline,
                size: 28,
                color: isCurrentTurn ? Theme.of(context).primaryColor : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: timeMs < 30000 ? Colors.red.withOpacity(0.2) : Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatTime(timeMs),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: timeMs < 30000 ? Colors.red : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(SocketConnectionState state) {
    Color color = Colors.grey;
    String tooltip = 'Unknown';

    switch (state) {
      case SocketConnectionState.connected:
        color = Colors.green;
        tooltip = 'Connected';
        break;
      case SocketConnectionState.connecting:
        color = Colors.orange;
        tooltip = 'Connecting...';
        break;
      case SocketConnectionState.reconnecting:
        color = Colors.yellow;
        tooltip = 'Reconnecting...';
        break;
      case SocketConnectionState.disconnected:
        color = Colors.red;
        tooltip = 'Disconnected';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
