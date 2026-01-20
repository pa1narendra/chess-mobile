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
  bool _isDialogShowing = false;
  late AnimationController _pulseController;
  StreamSubscription? _drawOfferSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    _drawOfferSubscription = gameProvider.drawOfferStream.listen((_) {
      if (mounted && !_isDialogShowing) {
        _showDrawOfferDialog();
      }
    });
    // Removed redundant Timer.periodic - GameProvider already notifies listeners on timer updates
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
    _drawOfferSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleMoveCallback(GameProvider game) {
    try {
      final gameState = game.controller.game;
      final history = gameState.history;
      debugPrint('[GameScreen] History length: ${history.length}');

      if (history.isNotEmpty) {
        final lastMove = history.last;
        final from = lastMove.move.fromAlgebraic;
        final to = lastMove.move.toAlgebraic;
        final promotion = lastMove.move.promotion?.name;
        debugPrint('[GameScreen] Move detected: $from -> $to, promotion: $promotion');

        if (game.isOfflineGame) {
          debugPrint('[GameScreen] Calling onUserMoveOffline');
          // Call async method and handle errors
          game.onUserMoveOffline(from, to, promotion: promotion).catchError((e, stackTrace) {
            debugPrint('[GameScreen] Error in onUserMoveOffline: $e');
            debugPrint('[GameScreen] Stack trace: $stackTrace');
          });
        } else {
          debugPrint('[GameScreen] Calling onUserMove');
          game.onUserMove(from, to, promotion: promotion);
        }
      } else {
        debugPrint('[GameScreen] History is empty, cannot detect move');
      }
    } catch (e, stackTrace) {
      debugPrint('[GameScreen] Error detecting move: $e');
      debugPrint('[GameScreen] Stack trace: $stackTrace');
    }
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

                // Opponent disconnection banner
                if (game.opponentDisconnected)
                  _buildDisconnectionBanner(game),

                // Game status display
                if (game.gameStatus != null)
                  _buildStatusBanner(game),

                // Analysis button
                if (game.gameStatus != null && 
                    game.gameStatus!.startsWith('Game Over') && 
                    !game.isOfflineGame && 
                    game.gameId != null &&
                    game.analysisResults == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton.icon(
                      onPressed: game.isAnalyzing ? null : () => game.analyzeGame(),
                      icon: game.isAnalyzing 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.analytics_outlined),
                      label: Text(game.isAnalyzing ? 'Analyzing...' : 'Analyze Game'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ),

                // Analysis Results
                if (game.analysisResults != null)
                   _buildAnalysisResults(game),

                // Move history display
                _buildMoveHistory(game),

                // Opponent info (shows pieces opponent has captured)
                _buildPlayerBar(
                  context,
                  game.playerColor == 'w' ? game.blackPlayerName : game.whitePlayerName,
                  game.playerColor == 'w' ? game.timeRemaining['b']! : game.timeRemaining['w']!,
                  isCurrentTurn: game.currentTurn != game.playerColor,
                  isOpponent: true,
                  isWhite: game.playerColor != 'w',
                  // Opponent captured player's pieces
                  capturedPieces: game.playerColor == 'w'
                      ? game.capturedPieces['black']!  // Black captured white pieces
                      : game.capturedPieces['white']!, // White captured black pieces
                  materialAdvantage: game.playerColor == 'w'
                      ? -game.materialAdvantage  // Invert for black's perspective
                      : game.materialAdvantage,
                ),

                // Chess Board with tap-to-move overlay
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final boardSize = constraints.maxWidth < constraints.maxHeight
                              ? constraints.maxWidth
                              : constraints.maxHeight;
                          final squareSize = boardSize / 8;

                          return SizedBox(
                            width: boardSize,
                            height: boardSize,
                            child: Stack(
                              children: [
                                // Chess Board - base layer
                                // Chess Board - wrapped with gesture detector for tap-to-move
                                // We wrap the board instead of overlaying to ensure drag events work
                                GestureDetector(
                                  // Only enable tap detection when it's user's turn and not viewing history
                                  onTapUp: (game.currentTurn == game.playerColor && !game.isViewingHistory) ? (details) {
                                    final localPosition = details.localPosition;
                                    final col = (localPosition.dx / squareSize).floor();
                                    final row = (localPosition.dy / squareSize).floor();

                                    // Ensure within bounds
                                    if (col >= 0 && col <= 7 && row >= 0 && row <= 7) {
                                      final square = _coordsToSquare(col, row, game.playerColor == 'w');
                                      debugPrint('[Tap] GestureDetector onTapUp: $square');
                                      game.selectSquare(square);
                                    }
                                  } : null,
                                  child: ChessBoard(
                                    controller: game.controller,
                                    enableUserMoves: game.currentTurn == game.playerColor && !game.isViewingHistory,
                                    boardColor: BoardColor.brown,
                                    boardOrientation: game.playerColor == 'w'
                                        ? PlayerColor.white
                                        : PlayerColor.black,
                                    onMove: () {
                                      debugPrint('[GameScreen] onMove callback fired! isOfflineGame: ${game.isOfflineGame}');
                                      // Clear selection after any move
                                      game.clearSelection();

                                      // Use a non-async approach to avoid callback issues
                                      _handleMoveCallback(game);
                                    },
                                  ),
                                ),

                                // Visual highlights (IgnorePointer) - display only
                                // Selected square highlight
                                if (game.selectedSquare != null)
                                  _buildSquareHighlight(
                                    game.selectedSquare!,
                                    squareSize,
                                    game.playerColor == 'w',
                                    AppColors.electricBlue.withOpacity(0.4),
                                  ),
                                // Legal moves highlights
                                ...game.legalMoves.map((square) => _buildLegalMoveIndicator(
                                  square,
                                  squareSize,
                                  game.playerColor == 'w',
                                  isCapture: game.captureMoves.contains(square),
                                )),

                                // Tap detection overlay removed - wrapped board instead
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Player info (shows pieces player has captured)
                _buildPlayerBar(
                  context,
                  game.playerColor == 'w' ? game.whitePlayerName : game.blackPlayerName,
                  game.playerColor == 'w' ? game.timeRemaining['w']! : game.timeRemaining['b']!,
                  isCurrentTurn: game.currentTurn == game.playerColor,
                  isOpponent: false,
                  isWhite: game.playerColor == 'w',
                  // Player captured opponent's pieces
                  capturedPieces: game.playerColor == 'w'
                      ? game.capturedPieces['white']!  // White captured black pieces
                      : game.capturedPieces['black']!, // Black captured white pieces
                  materialAdvantage: game.playerColor == 'w'
                      ? game.materialAdvantage
                      : -game.materialAdvantage,
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
    // Check if game is finished - just leave without confirmation
    final isGameOver = game.gameStatus != null && game.gameStatus!.startsWith('Game Over');

    if (isGameOver) {
      if (game.isOfflineGame) {
        game.stopOfflineGame();
      } else {
        game.leaveGame();
      }
      Navigator.of(context).pop();
      return;
    }

    // For offline bot games in progress
    if (game.isOfflineGame) {
      if (game.isInGame) {
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
            content: const Text('Your progress will be lost. Are you sure?'),
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

    // For online games in progress - show forfeit warning
    if (game.isInGame) {
      final shouldForfeit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.amberWarning),
              const SizedBox(width: 8),
              const Text('Forfeit Game?'),
            ],
          ),
          content: const Text('Leaving now will count as a loss. Are you sure you want to forfeit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Forfeit & Leave'),
            ),
          ],
        ),
      );

      if (shouldForfeit == true && context.mounted) {
        game.resign();
        game.leaveGame();
        Navigator.of(context).pop();
      }
    } else {
      // Not in game (waiting for opponent, etc.) - just leave
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

  Widget _buildDisconnectionBanner(GameProvider game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.amberWarning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amberWarning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: AppColors.amberWarning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              game.disconnectionMessage ?? 'Opponent disconnected. Waiting for reconnect...',
              style: TextStyle(color: AppColors.amberWarning, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.amberWarning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(BuildContext context, String name, int timeMs,
      {required bool isCurrentTurn, required bool isOpponent, required bool isWhite,
       List<String> capturedPieces = const [], int materialAdvantage = 0}) {
    final isUntimed = timeMs < 0;
    final isLowTime = !isUntimed && timeMs < 30000;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.hardEdge,
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

          // Name, captured pieces, and turn indicator
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    // Material advantage
                    if (materialAdvantage != 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          materialAdvantage > 0 ? '+$materialAdvantage' : '$materialAdvantage',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: materialAdvantage > 0 ? AppColors.emeraldGreen : AppColors.roseError,
                          ),
                        ),
                      ),
                  ],
                ),
                // Captured pieces display
                if (capturedPieces.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      capturedPieces.map((piece) => _getPieceSymbol(piece)).join(''),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  )
                else if (isCurrentTurn)
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 8),

          // Timer or Untimed indicator
          if (isUntimed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.purpleAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.purpleAccent.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.all_inclusive_rounded, color: AppColors.purpleAccent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Casual',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.purpleAccent,
                    ),
                  ),
                ],
              ),
            )
          else
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

  // Helper to convert piece letter to Unicode symbol
  String _getPieceSymbol(String piece) {
    switch (piece.toLowerCase()) {
      case 'p': return '♟';
      case 'n': return '♞';
      case 'b': return '♝';
      case 'r': return '♜';
      case 'q': return '♛';
      case 'k': return '♚';
      default: return piece;
    }
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
              game.resign(); // This sets the game over status for offline games
            },
            child: const Text('Give Up'),
          ),
        ],
      ),
    );
  }

  // Convert algebraic notation (e.g., "e4") to board coordinates
  (int, int) _squareToCoords(String square, bool isWhiteOrientation) {
    final file = square[0].codeUnitAt(0) - 'a'.codeUnitAt(0); // 0-7 for a-h
    final rank = int.parse(square[1]) - 1; // 0-7 for 1-8

    if (isWhiteOrientation) {
      return (file, 7 - rank); // White at bottom: rank 1 is at row 7
    } else {
      return (7 - file, rank); // Black at bottom: rank 8 is at row 0, file h is at col 0
    }
  }

  // Convert board coordinates to algebraic notation
  String _coordsToSquare(int col, int row, bool isWhiteOrientation) {
    int file, rank;
    if (isWhiteOrientation) {
      file = col;
      rank = 7 - row;
    } else {
      file = 7 - col;
      rank = row;
    }
    return '${String.fromCharCode('a'.codeUnitAt(0) + file)}${rank + 1}';
  }

  Widget _buildSquareHighlight(String square, double squareSize, bool isWhiteOrientation, Color color) {
    final (col, row) = _squareToCoords(square, isWhiteOrientation);
    return Positioned(
      left: col * squareSize,
      top: row * squareSize,
      child: IgnorePointer(
        child: Container(
          width: squareSize,
          height: squareSize,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: AppColors.electricBlue,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegalMoveIndicator(String square, double squareSize, bool isWhiteOrientation, {bool isCapture = false}) {
    final (col, row) = _squareToCoords(square, isWhiteOrientation);
    return Positioned(
      left: col * squareSize,
      top: row * squareSize,
      child: IgnorePointer(
        child: Container(
          width: squareSize,
          height: squareSize,
          alignment: Alignment.center,
          child: isCapture
              // Capture indicator: ring around the piece
              ? Container(
                  width: squareSize * 0.9,
                  height: squareSize * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.roseError.withOpacity(0.8),
                      width: 3,
                    ),
                  ),
                )
              // Move indicator: small circle
              : Container(
                  width: squareSize * 0.35,
                  height: squareSize * 0.35,
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withOpacity(0.7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.tealAccent.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMoveHistory(GameProvider game) {
    // Get move history
    List<String> moves = [];

    if (game.isOfflineGame) {
      // For offline games, use the maintained history (controller.loadFen resets internal history)
      moves = game.moveHistory;
    } else {
      // For online games, use controller.getSan()
      try {
        final sanMoves = game.controller.getSan();
        if (sanMoves != null && sanMoves.isNotEmpty) {
          moves = List<String>.from(sanMoves);
        }
      } catch (e) {
        debugPrint('Error getting move history: $e');
      }
    }

    if (moves.isEmpty) {
      return Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: Center(
          child: Text(
            'No moves yet',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    final isViewingHistory = game.isViewingHistory;
    final viewingIndex = game.viewingMoveIndex;

    // Format moves as pairs (1. e4 e5 2. Nf3 Nc6 ...)
    final formattedMoves = <Widget>[];
    for (int i = 0; i < moves.length; i++) {
      if (i % 2 == 0) {
        // White's move - add move number
        final moveNumber = (i ~/ 2) + 1;
        formattedMoves.add(
          Container(
            margin: const EdgeInsets.only(right: 4),
            child: Text(
              '$moveNumber.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }

      final isLastMove = i == moves.length - 1 && !isViewingHistory;
      final isViewingThisMove = isViewingHistory && viewingIndex == i + 1; // +1 because fenHistory[0] is starting position
      final moveIndex = i;

      formattedMoves.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // FEN history: index 0 is start position, index 1 is after move 0, etc.
            // So to view position after move i, we use fenHistory[i+1]
            debugPrint('[MoveHistory] Tapped move $moveIndex, fenHistory: ${game.fenHistory.length}');
            if (game.fenHistory.length > moveIndex + 1) {
              game.viewMove(moveIndex + 1);
            }
          },
          child: Container(
            margin: EdgeInsets.only(right: i % 2 == 0 ? 2 : 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: isViewingThisMove
                ? BoxDecoration(
                    color: AppColors.purpleAccent.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.purpleAccent),
                  )
                : isLastMove
                    ? BoxDecoration(
                        color: AppColors.tealAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.tealAccent.withOpacity(0.5)),
                      )
                    : null,
            child: Text(
              moves[i],
              style: TextStyle(
                color: isViewingThisMove
                    ? AppColors.purpleAccent
                    : isLastMove
                        ? AppColors.tealAccent
                        : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: (isLastMove || isViewingThisMove) ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    // Add "back to current" button when viewing history
    if (isViewingHistory) {
      formattedMoves.add(
        GestureDetector(
          onTap: () => game.viewCurrentPosition(),
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.tealAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.tealAccent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.skip_next_rounded, size: 14, color: AppColors.tealAccent),
                const SizedBox(width: 2),
                Text(
                  'Live',
                  style: TextStyle(
                    color: AppColors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isViewingHistory
            ? AppColors.purpleAccent.withOpacity(0.1)
            : AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isViewingHistory ? AppColors.purpleAccent : AppColors.borderColor,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: !isViewingHistory, // Only auto-scroll to end if not viewing history
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: formattedMoves,
        ),
      ),
    );
  }

  Widget _buildTapOverlay(double squareSize, bool isWhiteOrientation, GameProvider game) {
    // Use GestureDetector with only onTapUp - this will LOSE to drag gestures
    // in the gesture arena, allowing ChessBoard's drag-and-drop to work
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        // This only fires if no drag occurred (tap recognizer loses to drag recognizer)
        final localPosition = details.localPosition;
        final col = (localPosition.dx / squareSize).floor();
        final row = (localPosition.dy / squareSize).floor();

        // Ensure within bounds
        if (col >= 0 && col <= 7 && row >= 0 && row <= 7) {
          final square = _coordsToSquare(col, row, isWhiteOrientation);
          debugPrint('[Tap] GestureDetector onTapUp: $square');
          game.selectSquare(square);
        }
      },
      child: Container(
        color: Colors.transparent,
      ),
    );
  }

  Widget _buildAnalysisResults(GameProvider game) {
    final results = game.analysisResults;
    if (results == null) return const SizedBox.shrink();

    final analysis = results['analysis'];
    if (analysis == null) return const SizedBox.shrink();

    // Handle both 'evaluations' (old) and 'keyMoments' (new schema)
    final evaluations = (analysis['evaluations'] ?? analysis['keyMoments'] ?? []) as List;

    if (evaluations.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.emeraldGreen),
            const SizedBox(width: 8),
            const Text('Great game! No major mistakes found.'),
          ],
        ),
      );
    }

    // Count stats - only count significant moves
    int blunders = 0;
    int mistakes = 0;
    int inaccuracies = 0;

    for (var ev in evaluations) {
      final classification = ev['classification']?.toString();
      if (classification == 'blunder') blunders++;
      else if (classification == 'mistake') mistakes++;
      else if (classification == 'inaccuracy') inaccuracies++;
    }

    // Filter to only show important moves (not 'good', 'book', 'best')
    final significantMoves = evaluations.where((ev) {
      final c = ev['classification']?.toString();
      return c == 'blunder' || c == 'mistake' || c == 'inaccuracy' || c == 'brilliant' || c == 'great';
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats, color: AppColors.electricBlue),
              const SizedBox(width: 8),
              const Text('Analysis Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          // Accuracy display
          if (analysis['accuracy'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAccuracyItem('White', analysis['accuracy']['w'] ?? 0),
                  _buildAccuracyItem('Black', analysis['accuracy']['b'] ?? 0),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Blunders', blunders, AppColors.roseError),
              _buildStatItem('Mistakes', mistakes, AppColors.amberWarning),
              _buildStatItem('Inaccuracies', inaccuracies, Colors.orange),
            ],
          ),
          if (significantMoves.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: significantMoves.length,
                itemBuilder: (context, index) {
                  final eval = significantMoves[index];
                  final classification = eval['classification']?.toString() ?? '';

                  Color color = Colors.grey;
                  if (classification == 'blunder') color = AppColors.roseError;
                  else if (classification == 'mistake') color = AppColors.amberWarning;
                  else if (classification == 'inaccuracy') color = Colors.orange;
                  else if (classification == 'brilliant') color = AppColors.tealAccent;
                  else if (classification == 'great') color = AppColors.emeraldGreen;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${eval['moveIndex'] ?? index + 1}.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            eval['san'] ?? eval['move'] ?? 'Move ${eval['moveIndex']}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            classification.toUpperCase(),
                            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(value.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildAccuracyItem(String label, int accuracy) {
    Color color;
    if (accuracy >= 90) {
      color = AppColors.emeraldGreen;
    } else if (accuracy >= 70) {
      color = AppColors.tealAccent;
    } else if (accuracy >= 50) {
      color = AppColors.amberWarning;
    } else {
      color = AppColors.roseError;
    }

    return Column(
      children: [
        Text(
          '$accuracy%',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
