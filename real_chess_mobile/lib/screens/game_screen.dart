import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../providers/game_provider.dart';
import '../api/socket_service.dart';
import '../main.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _isDialogShowing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.drawOfferStream.listen((_) {
      if (mounted && !_isDialogShowing) {
        _showDrawOfferDialog();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _showDrawOfferDialog() {
    setState(() => _isDialogShowing = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.handshake_rounded, color: AppColors.amberWarning),
            const SizedBox(width: 8),
            const Text('Draw Offered'),
          ],
        ),
        content: const Text('Your opponent has offered a draw. Do you accept?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isDialogShowing = false);
              Provider.of<GameProvider>(context, listen: false).declineDraw();
            },
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isDialogShowing = false);
              Provider.of<GameProvider>(context, listen: false).acceptDraw();
            },
            child: const Text('Accept Draw'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
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
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => _handleBackPress(context, game),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.grid_view_rounded, size: 20),
                const SizedBox(width: 8),
                Text(game.gameCode != null ? 'Code: ${game.gameCode}' : 'Game'),
              ],
            ),
            actions: [
              if (!game.isOfflineGame) _buildConnectionIndicator(game.connectionState),
              if (game.isOfflineGame)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.purpleAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.computer_rounded, color: AppColors.purpleAccent, size: 20),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'resign') {
                    if (game.isOfflineGame) {
                      _showGiveUpConfirmation(context, game);
                    } else {
                      _showResignConfirmation(context);
                    }
                  } else if (value == 'draw') {
                    game.offerDraw();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            const Text('Draw offer sent'),
                          ],
                        ),
                        backgroundColor: AppColors.tealAccent,
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  if (!game.isOfflineGame)
                    PopupMenuItem(
                      value: 'draw',
                      child: Row(
                        children: [
                          Icon(Icons.handshake_rounded, color: AppColors.amberWarning),
                          const SizedBox(width: 12),
                          const Text('Offer Draw'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'resign',
                    child: Row(
                      children: [
                        Icon(Icons.flag_rounded, color: AppColors.roseError),
                        const SizedBox(width: 12),
                        Text(game.isOfflineGame ? 'Give Up' : 'Resign'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              _handleBackPress(context, game);
            },
            child: Column(
              children: [
                // Error message display
                if (game.errorMessage != null)
                  _buildErrorBanner(game),

                // Game status display
                if (game.gameStatus != null)
                  _buildStatusBanner(game),

                // Opponent info
                _buildPlayerBar(
                  context,
                  game.playerColor == 'w' ? game.blackPlayerName : game.whitePlayerName,
                  game.playerColor == 'w' ? game.timeRemaining['b']! : game.timeRemaining['w']!,
                  isCurrentTurn: game.currentTurn != game.playerColor,
                  isOpponent: true,
                  isWhite: game.playerColor != 'w',
                ),

                // Chess Board
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ChessBoard(
                        controller: game.controller,
                        enableUserMoves: game.currentTurn == game.playerColor,
                        boardColor: BoardColor.brown,
                        boardOrientation: game.playerColor == 'w'
                            ? PlayerColor.white
                            : PlayerColor.black,
                        onMove: () {
                          try {
                            final moveHistory = game.controller.getSan();
                            if (moveHistory != null && moveHistory.isNotEmpty) {
                              final gameState = game.controller.game;
                              final history = gameState.history;
                              if (history.isNotEmpty) {
                                final lastMove = history.last;
                                final from = lastMove.move.fromAlgebraic;
                                final to = lastMove.move.toAlgebraic;
                                final promotion = lastMove.move.promotion?.name;
                                if (game.isOfflineGame) {
                                  game.onUserMoveOffline(from, to, promotion: promotion);
                                } else {
                                  game.onUserMove(from, to, promotion: promotion);
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint('Error detecting move: $e');
                          }
                        },
                      ),
                    ),
                  ),
                ),

                // Player info
                _buildPlayerBar(
                  context,
                  game.playerColor == 'w' ? game.whitePlayerName : game.blackPlayerName,
                  game.playerColor == 'w' ? game.timeRemaining['w']! : game.timeRemaining['b']!,
                  isCurrentTurn: game.currentTurn == game.playerColor,
                  isOpponent: false,
                  isWhite: game.playerColor == 'w',
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleBackPress(BuildContext context, GameProvider game) async {
    // For offline games, just confirm and leave
    if (game.isOfflineGame) {
      if (game.isInGame && (game.gameStatus == null || !game.gameStatus!.startsWith('Game Over'))) {
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.amberWarning),
                const SizedBox(width: 8),
                const Text('Leave Game?'),
              ],
            ),
            content: const Text('Are you sure you want to leave this game?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );

        if (shouldLeave == true && context.mounted) {
          game.stopOfflineGame();
          Navigator.of(context).pop();
        }
      } else {
        game.stopOfflineGame();
        Navigator.of(context).pop();
      }
      return;
    }

    // For online games
    if (game.isInGame && game.gameStatus != null && !game.gameStatus!.startsWith('Game Over')) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.amberWarning),
              const SizedBox(width: 8),
              const Text('Leave Game?'),
            ],
          ),
          content: const Text('Leaving now will forfeit the game. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
              onPressed: () {
                game.resign();
                Navigator.pop(ctx, true);
              },
              child: const Text('Leave & Resign'),
            ),
          ],
        ),
      );

      if (shouldLeave == true && context.mounted) {
        game.leaveGame();
        Navigator.of(context).pop();
      }
    } else {
      game.leaveGame();
      Navigator.of(context).pop();
    }
  }

  Widget _buildErrorBanner(GameProvider game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.roseError.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.roseError.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.roseError, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              game.errorMessage!,
              style: TextStyle(color: AppColors.roseError, fontSize: 14),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: AppColors.roseError),
            onPressed: () => game.clearError(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(GameProvider game) {
    final isGameOver = game.gameStatus!.startsWith('Game Over');
    final color = isGameOver ? AppColors.electricBlue : AppColors.tealAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isGameOver ? Icons.emoji_events_rounded : Icons.hourglass_top_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              game.gameStatus!,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(BuildContext context, String name, int timeMs,
      {required bool isCurrentTurn, required bool isOpponent, required bool isWhite}) {
    final isLowTime = timeMs < 30000;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? AppColors.tealAccent.withOpacity(0.1)
            : AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn ? AppColors.tealAccent : AppColors.borderColor,
          width: isCurrentTurn ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Player avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isWhite ? Colors.white : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrentTurn ? AppColors.tealAccent : AppColors.borderColor,
              ),
              boxShadow: isCurrentTurn
                  ? [
                      BoxShadow(
                        color: AppColors.tealAccent.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                isWhite ? '♔' : '♚',
                style: TextStyle(
                  fontSize: 24,
                  color: isWhite ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name and turn indicator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (isCurrentTurn)
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.tealAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOpponent ? 'Their turn' : 'Your turn',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.tealAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Timer
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isLowTime
                      ? AppColors.roseError.withOpacity(
                          isCurrentTurn ? 0.2 + (_pulseController.value * 0.1) : 0.2)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: isLowTime
                      ? Border.all(color: AppColors.roseError, width: 1.5)
                      : null,
                ),
                child: Text(
                  _formatTime(timeMs),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: isLowTime ? AppColors.roseError : AppColors.textPrimary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(SocketConnectionState state) {
    Color color;
    IconData icon;

    switch (state) {
      case SocketConnectionState.connected:
        color = AppColors.emeraldGreen;
        icon = Icons.wifi_rounded;
        break;
      case SocketConnectionState.connecting:
        color = AppColors.amberWarning;
        icon = Icons.wifi_find_rounded;
        break;
      case SocketConnectionState.reconnecting:
        color = AppColors.amberWarning;
        icon = Icons.wifi_find_rounded;
        break;
      case SocketConnectionState.disconnected:
        color = AppColors.roseError;
        icon = Icons.wifi_off_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _showResignConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_rounded, color: AppColors.roseError),
            const SizedBox(width: 8),
            const Text('Resign?'),
          ],
        ),
        content: const Text('Are you sure you want to resign this game? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
            onPressed: () {
              Provider.of<GameProvider>(context, listen: false).resign();
              Navigator.pop(ctx);
            },
            child: const Text('Resign'),
          ),
        ],
      ),
    );
  }

  void _showGiveUpConfirmation(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_rounded, color: AppColors.roseError),
            const SizedBox(width: 8),
            const Text('Give Up?'),
          ],
        ),
        content: const Text('Are you sure you want to give up this game against the bot?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
            onPressed: () {
              Navigator.pop(ctx);
              game.stopOfflineGame();
              Navigator.of(context).pop();
            },
            child: const Text('Give Up'),
          ),
        ],
      ),
    );
  }
}
