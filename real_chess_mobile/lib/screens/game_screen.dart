import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import '../providers/game_provider.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        return WillPopScope(
            onWillPop: () async {
                game.leaveGame();
                return true;
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
            ),
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 const Padding(
                   padding: EdgeInsets.all(8.0),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.person, size: 32),
                       SizedBox(width: 8),
                       Text('Opponent', style: TextStyle(fontSize: 20)),
                     ],
                   ),
                 ),
                 
                Expanded(
                  child: Center(
                    child: ChessBoard(
                      controller: game.controller,
                      boardColor: BoardColor.brown,
                      boardOrientation: game.playerColor == 'w' ? PlayerColor.white : PlayerColor.black,

                    ),
                  ),
                ),
                
                const Padding(
                   padding: EdgeInsets.all(8.0),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.person_outline, size: 32),
                       SizedBox(width: 8),
                       Text('You', style: TextStyle(fontSize: 20)),
                     ],
                   ),
                 ),
              ],
            ),
          ),
        );
      },
    );
  }
}
