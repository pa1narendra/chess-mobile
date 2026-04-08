import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;
import '../providers/game_provider.dart';
import '../api/socket_service.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../widgets/custom_chess_board.dart';
import '../main.dart';
import 'analysis_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  bool _isDialogShowing = false;
  bool _hasShownGameOverOverlay = false;
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
        // Trigger post-game overlay once
        final isGameOver = game.gameStatus != null && game.gameStatus!.startsWith('Game Over');
        if (isGameOver && !_hasShownGameOverOverlay) {
          _hasShownGameOverOverlay = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showGameOverOverlay(context, game);
          });
        } else if (!isGameOver) {
          _hasShownGameOverOverlay = false;
        }

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
              if (!game.isOfflineGame && game.isInGame)
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      onPressed: () => _openChatSheet(context, game),
                      tooltip: 'Chat',
                    ),
                    if (game.unreadChatCount > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: AppColors.roseError, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            game.unreadChatCount > 9 ? '9+' : '${game.unreadChatCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              if (!(game.gameStatus != null && game.gameStatus!.startsWith('Game Over')))
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
                // Top section: banners, status, analysis — shrinkable when game over
                // Error and disconnection banners (non-game-over)
                if (game.errorMessage != null)
                  _buildErrorBanner(game),
                if (game.opponentDisconnected)
                  _buildDisconnectionBanner(game),
                // Non-game-over status (e.g., "Waiting for opponent")
                if (game.gameStatus != null && !game.gameStatus!.startsWith('Game Over'))
                  _buildStatusBanner(game),

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
                                  child: CustomChessBoard(
                                    controller: game.controller,
                                    enableUserMoves: game.currentTurn == game.playerColor && !game.isViewingHistory,
                                    boardOrientation: game.playerColor == 'w'
                                        ? PlayerColor.white
                                        : PlayerColor.black,
                                    onMove: () {
                                      debugPrint('[GameScreen] onMove callback fired! isOfflineGame: ${game.isOfflineGame}');
                                      game.clearSelection();
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

  void _openChatSheet(BuildContext context, GameProvider game) {
    game.setChatOpen(true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ChatSheet(game: game),
    ).whenComplete(() => game.setChatOpen(false));
  }

  void _showGameOverOverlay(BuildContext context, GameProvider game) {
    final status = game.gameStatus ?? '';
    final isDraw = status.contains('draw') || status.contains('Draw') || status.contains('stalemate');
    final playerColor = game.playerColor;
    final isWin = !isDraw && status.contains('Winner: $playerColor');

    Color resultColor;
    String resultTitle;
    IconData resultIcon;

    if (isDraw) {
      resultColor = AppColors.amberWarning;
      resultTitle = 'Draw';
      resultIcon = Icons.handshake;
    } else if (isWin) {
      resultColor = AppColors.emeraldGreen;
      resultTitle = 'Victory!';
      resultIcon = Icons.emoji_events;
    } else {
      resultColor = AppColors.roseError;
      resultTitle = 'Defeat';
      resultIcon = Icons.close;
    }

    String reason = '';
    if (status.contains('checkmate')) reason = 'by checkmate';
    else if (status.contains('timeout')) reason = 'on time';
    else if (status.contains('resignation')) reason = 'by resignation';
    else if (status.contains('stalemate')) reason = 'by stalemate';
    else if (status.contains('agreement')) reason = 'by mutual agreement';
    else if (status.contains('disconnection')) reason = 'by disconnection';

    int? ratingChange;
    final ratingChanges = game.ratingChanges;
    if (ratingChanges != null && playerColor != null) {
      final change = ratingChanges[playerColor];
      if (change is num) ratingChange = change.toInt();
    }

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Icon(resultIcon, color: resultColor, size: 48),
            const SizedBox(height: 12),
            Text(resultTitle, style: TextStyle(color: resultColor, fontSize: 28, fontWeight: FontWeight.w800)),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(reason, style: TextStyle(color: resultColor.withValues(alpha: 0.7), fontSize: 15)),
              ),
            if (ratingChange != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.deepDark, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Rating ', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                    Icon(
                      ratingChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      color: ratingChange >= 0 ? AppColors.emeraldGreen : AppColors.roseError,
                      size: 20,
                    ),
                    Text(
                      ratingChange >= 0 ? '+$ratingChange' : '$ratingChange',
                      style: TextStyle(color: ratingChange >= 0 ? AppColors.emeraldGreen : AppColors.roseError, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            // Action buttons
            Row(
              children: [
                // Analyze (only for online games)
                if (!game.isOfflineGame && game.gameId != null)
                  Expanded(
                    child: _overlayButton(Icons.analytics_outlined, 'Analyze', AppColors.electricBlue, () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(gameId: game.gameId!)));
                    }),
                  ),
                if (!game.isOfflineGame && game.gameId != null) const SizedBox(width: 12),
                // Home
                Expanded(
                  child: _overlayButton(Icons.home_rounded, 'Home', AppColors.tealAccent, () {
                    Navigator.pop(ctx);
                    if (game.isOfflineGame) {
                      game.stopOfflineGame();
                    } else {
                      game.leaveGame();
                    }
                    Navigator.of(context).pop();
                  }),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _overlayButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
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

    if (!isGameOver) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.tealAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.tealAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top_rounded, color: AppColors.tealAccent, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(game.gameStatus!, style: const TextStyle(color: AppColors.tealAccent, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    // Parse result from status string
    final status = game.gameStatus!;
    final isDraw = status.contains('draw') || status.contains('Draw') || status.contains('stalemate');
    final playerColor = game.playerColor;
    final isWin = !isDraw && status.contains('Winner: $playerColor');
    final isLoss = !isDraw && !isWin;

    Color resultColor;
    String resultTitle;
    IconData resultIcon;

    if (isDraw) {
      resultColor = AppColors.amberWarning;
      resultTitle = 'Draw';
      resultIcon = Icons.handshake;
    } else if (isWin) {
      resultColor = AppColors.emeraldGreen;
      resultTitle = 'Victory!';
      resultIcon = Icons.emoji_events;
    } else {
      resultColor = AppColors.roseError;
      resultTitle = 'Defeat';
      resultIcon = Icons.close;
    }

    // Extract reason
    String reason = '';
    if (status.contains('checkmate')) reason = 'by checkmate';
    else if (status.contains('timeout')) reason = 'on time';
    else if (status.contains('resignation')) reason = 'by resignation';
    else if (status.contains('stalemate')) reason = 'by stalemate';
    else if (status.contains('agreement')) reason = 'by mutual agreement';
    else if (status.contains('disconnection')) reason = 'by disconnection';

    // Rating change
    final ratingChanges = game.ratingChanges;
    int? ratingChange;
    if (ratingChanges != null && playerColor != null) {
      final change = ratingChanges[playerColor];
      if (change is num) ratingChange = change.toInt();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: resultColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: resultColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(resultIcon, color: resultColor, size: 36),
          const SizedBox(height: 8),
          Text(
            resultTitle,
            style: TextStyle(color: resultColor, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(reason, style: TextStyle(color: resultColor.withValues(alpha: 0.7), fontSize: 14)),
            ),
          if (ratingChange != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Rating ', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  Icon(
                    ratingChange >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: ratingChange >= 0 ? AppColors.emeraldGreen : AppColors.roseError,
                    size: 18,
                  ),
                  Text(
                    ratingChange >= 0 ? '+$ratingChange' : '$ratingChange',
                    style: TextStyle(
                      color: ratingChange >= 0 ? AppColors.emeraldGreen : AppColors.roseError,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            const Flexible(child: Text('Great game! No major mistakes found.')),
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
              Icon(Icons.query_stats, color: AppColors.electricBlue, size: 20),
              const SizedBox(width: 8),
              const Flexible(child: Text('Analysis Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
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
                            color: color.withValues(alpha: 0.2),
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

class _ChatSheet extends StatefulWidget {
  final GameProvider game;
  const _ChatSheet({required this.game});
  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _showEmoji = false;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onUpdate);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmoji) {
        setState(() => _showEmoji = false);
      }
    });
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.game.removeListener(_onUpdate);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.game.sendChatMessage(text);
    _controller.clear();
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() => _showEmoji = !_showEmoji);
  }

  @override
  Widget build(BuildContext context) {
    final isGameOver = widget.game.gameStatus != null && widget.game.gameStatus!.startsWith('Game Over');
    final messages = widget.game.chatMessages;

    return Padding(
      padding: EdgeInsets.only(bottom: _showEmoji ? 0 : MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * (_showEmoji ? 0.75 : 0.45),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderColor, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.chat_bubble_rounded, color: AppColors.tealAccent, size: 20),
                    const SizedBox(width: 8),
                    const Flexible(child: Text('Game Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                  ]),
                ],
              ),
            ),
            const Divider(color: AppColors.borderColor, height: 1),
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('No messages yet', style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = messages[i];
                        final isMe = msg.sender == widget.game.playerColor;
                        return _buildBubble(msg, isMe);
                      },
                    ),
            ),
            if (!isGameOver)
              Container(
                padding: EdgeInsets.fromLTRB(8, 8, 8, _showEmoji ? 0 : 8 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderColor))),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLength: 200,
                        maxLines: 1,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: true,
                          fillColor: AppColors.deepDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _toggleEmoji,
                    ),
                    IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.tealAccent), onPressed: _send),
                  ],
                ),
              ),
            if (_showEmoji && !isGameOver)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _controller.text += emoji.emoji;
                    _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
                  },
                  config: Config(
                    bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                    categoryViewConfig: const CategoryViewConfig(
                      iconColorSelected: AppColors.tealAccent,
                      indicatorColor: AppColors.tealAccent,
                    ),
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: AppColors.surfaceDark,
                      columns: 8,
                      emojiSizeMax: 28,
                    ),
                    searchViewConfig: const SearchViewConfig(
                      backgroundColor: AppColors.surfaceDark,
                      buttonIconColor: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, bool isMe) {
    final time = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMe ? AppColors.tealAccent.withValues(alpha: 0.15) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMe ? AppColors.tealAccent.withValues(alpha: 0.3) : AppColors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(msg.senderName, style: const TextStyle(fontSize: 11, color: AppColors.electricBlue, fontWeight: FontWeight.w600)),
              ),
            Text(msg.message, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Align(alignment: Alignment.bottomRight, child: Text(timeStr, style: const TextStyle(fontSize: 10, color: AppColors.textMuted))),
          ],
        ),
      ),
    );
  }
}
