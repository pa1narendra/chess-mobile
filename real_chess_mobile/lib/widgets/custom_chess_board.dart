import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess show Chess, Color;
import 'package:chess_vectors_flutter/chess_vectors_flutter.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' hide BoardColor;
import '../main.dart';

/// Chess.com-inspired board theme
class ChessBoardTheme {
  final ui.Color lightSquare;
  final ui.Color darkSquare;
  final ui.Color coordinateLight;
  final ui.Color coordinateDark;

  const ChessBoardTheme({
    required this.lightSquare,
    required this.darkSquare,
    required this.coordinateLight,
    required this.coordinateDark,
  });

  static const green = ChessBoardTheme(
    lightSquare: ui.Color.from(alpha: 1.0, red: 0.922, green: 0.925, blue: 0.816),
    darkSquare: ui.Color.from(alpha: 1.0, red: 0.467, green: 0.584, blue: 0.337),
    coordinateLight: ui.Color.from(alpha: 1.0, red: 0.467, green: 0.584, blue: 0.337),
    coordinateDark: ui.Color.from(alpha: 1.0, red: 0.922, green: 0.925, blue: 0.816),
  );
}

const _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// Build a chess piece SVG widget with proper styling
Widget _buildPieceSvg(String pieceCode, double size) {
  switch (pieceCode) {
    case 'WP': return WhitePawn(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'WR': return WhiteRook(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'WN': return WhiteKnight(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'WB': return WhiteBishop(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'WQ': return WhiteQueen(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'WK': return WhiteKing(size: size, fillColor: Colors.white, strokeColor: const ui.Color.from(alpha: 1, red: 0.17, green: 0.17, blue: 0.17));
    case 'BP': return BlackPawn(size: size);
    case 'BR': return BlackRook(size: size);
    case 'BN': return BlackKnight(size: size);
    case 'BB': return BlackBishop(size: size);
    case 'BQ': return BlackQueen(size: size);
    case 'BK': return BlackKing(size: size);
    default: return const SizedBox();
  }
}

class CustomChessBoard extends StatefulWidget {
  final ChessBoardController controller;
  final bool enableUserMoves;
  final PlayerColor boardOrientation;
  final VoidCallback? onMove;
  final ChessBoardTheme theme;

  const CustomChessBoard({
    super.key,
    required this.controller,
    this.enableUserMoves = true,
    this.boardOrientation = PlayerColor.white,
    this.onMove,
    this.theme = ChessBoardTheme.green,
  });

  @override
  State<CustomChessBoard> createState() => _CustomChessBoardState();
}

class _CustomChessBoardState extends State<CustomChessBoard> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<chess.Chess>(
      valueListenable: widget.controller,
      builder: (context, game, _) {
        return AspectRatio(
          aspectRatio: 1.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boardSize = constraints.maxWidth;
              final squareSize = boardSize / 8;

              return Stack(
                children: [
                  _buildBoard(squareSize),
                  _buildPieces(game, squareSize),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBoard(double squareSize) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final row = index ~/ 8;
        final col = index % 8;
        final isLight = (row + col) % 2 == 0;

        final isBottomRank = row == 7;
        final isLeftCol = col == 0;
        final fileLabel = widget.boardOrientation == PlayerColor.white
            ? _files[col]
            : _files[7 - col];
        final rankLabel = widget.boardOrientation == PlayerColor.white
            ? '${8 - row}'
            : '${row + 1}';

        return Container(
          width: squareSize,
          height: squareSize,
          color: isLight ? widget.theme.lightSquare : widget.theme.darkSquare,
          child: Stack(
            children: [
              if (isLeftCol)
                Positioned(
                  top: 2,
                  left: 3,
                  child: Text(
                    rankLabel,
                    style: TextStyle(
                      color: isLight ? widget.theme.coordinateLight : widget.theme.coordinateDark,
                      fontSize: squareSize * 0.17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (isBottomRank)
                Positioned(
                  bottom: 1,
                  right: 3,
                  child: Text(
                    fileLabel,
                    style: TextStyle(
                      color: isLight ? widget.theme.coordinateLight : widget.theme.coordinateDark,
                      fontSize: squareSize * 0.17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPieces(chess.Chess game, double squareSize) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final row = index ~/ 8;
        final col = index % 8;

        final boardRank = widget.boardOrientation == PlayerColor.black
            ? '${row + 1}'
            : '${(7 - row) + 1}';
        final boardFile = widget.boardOrientation == PlayerColor.white
            ? _files[col]
            : _files[7 - col];
        final squareName = '$boardFile$boardRank';
        final pieceOnSquare = game.get(squareName);

        if (pieceOnSquare == null) {
          return _buildDropTarget(game, squareName, squareSize, Container());
        }

        final pieceCode = (pieceOnSquare.color == chess.Color.WHITE ? 'W' : 'B') +
            (pieceOnSquare.type.toUpperCase());
        final pieceWidget = SizedBox(
          width: squareSize,
          height: squareSize,
          child: FittedBox(child: _buildPieceSvg(pieceCode, 45)),
        );

        final isCurrentTurnPiece = pieceOnSquare.color == game.turn;
        if (!widget.enableUserMoves || !isCurrentTurnPiece) {
          return _buildDropTarget(game, squareName, squareSize, pieceWidget);
        }

        final draggable = Draggable<_PieceDragData>(
          data: _PieceDragData(
            squareName: squareName,
            pieceType: pieceOnSquare.type.toUpperCase(),
            pieceColor: pieceOnSquare.color,
          ),
          feedback: SizedBox(
            width: squareSize * 1.2,
            height: squareSize * 1.2,
            child: FittedBox(child: _buildPieceSvg(pieceCode, 45)),
          ),
          childWhenDragging: const SizedBox(),
          child: pieceWidget,
        );

        return _buildDropTarget(game, squareName, squareSize, draggable);
      },
    );
  }

  Widget _buildDropTarget(chess.Chess game, String squareName, double squareSize, Widget child) {
    return DragTarget<_PieceDragData>(
      builder: (context, candidateData, rejectedData) => child,
      onWillAcceptWithDetails: (data) => widget.enableUserMoves,
      onAcceptWithDetails: (details) async {
        final data = details.data;
        if (data.pieceColor != game.turn) return;

        final moveColor = game.turn;

        if (data.pieceType == "P" &&
            ((data.squareName[1] == "7" && squareName[1] == "8" && data.pieceColor == chess.Color.WHITE) ||
             (data.squareName[1] == "2" && squareName[1] == "1" && data.pieceColor == chess.Color.BLACK))) {
          final promotion = await _showPromotionDialog(context, data.pieceColor == chess.Color.WHITE);
          if (promotion != null) {
            widget.controller.makeMoveWithPromotion(
              from: data.squareName,
              to: squareName,
              pieceToPromoteTo: promotion,
            );
          } else {
            return;
          }
        } else {
          widget.controller.makeMove(from: data.squareName, to: squareName);
        }

        if (game.turn != moveColor) {
          widget.onMove?.call();
        }
      },
    );
  }

  Future<String?> _showPromotionDialog(BuildContext context, bool isWhite) {
    final pieces = isWhite
        ? [('q', WhiteQueen(size: 36)), ('r', WhiteRook(size: 36)), ('b', WhiteBishop(size: 36)), ('n', WhiteKnight(size: 36))]
        : [('q', BlackQueen(size: 36)), ('r', BlackRook(size: 36)), ('b', BlackBishop(size: 36)), ('n', BlackKnight(size: 36))];

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Promote to', style: TextStyle(color: AppColors.textPrimary)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: pieces.map((p) {
            return GestureDetector(
              onTap: () => Navigator.of(ctx).pop(p.$1),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(width: 36, height: 36, child: p.$2),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PieceDragData {
  final String squareName;
  final String pieceType;
  final chess.Color pieceColor;

  _PieceDragData({
    required this.squareName,
    required this.pieceType,
    required this.pieceColor,
  });
}
