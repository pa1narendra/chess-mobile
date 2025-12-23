import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import '../api/socket_service.dart';

class GameProvider with ChangeNotifier {
  SocketService? _socket;
  ChessBoardController controller = ChessBoardController();
  
  String? _gameId;
  String _playerColor = 'w'; // 'w' or 'b'
  
  bool _isInGame = false;
  String? _gameStatus; // 'Checkmate', 'Draw', etc.
  
  // Pending games list
  List<dynamic> _pendingGames = [];

  bool _isServerUpdate = false;

  GameProvider() {
    controller.addListener(_onBoardChange);
  }

  bool get isInGame => _isInGame;
  String? get gameId => _gameId;
  String get playerColor => _playerColor;
  List<dynamic> get pendingGames => _pendingGames;

  void initSocket(String token) {
    if (_socket != null) return;
    
    _socket = SocketService(onMessage: _onMessage);
    _socket!.connect(token);
  }

  void _onMessage(dynamic msg) {
    print('GameProvider received: ${msg['type']}');
    
    switch (msg['type']) {
      case 'GAME_CREATED':
      case 'GAME_JOINED':
        _gameId = msg['gameId'];
        _playerColor = msg['color']; // 'w' or 'b'
        _isInGame = true;
        
        if (msg['fen'] != null) {
          receiveMove(msg['fen']);
        } else {
             controller.resetBoard();
        }
        notifyListeners();
        break;
        
      case 'UPDATE_BOARD':
        if (msg['fen'] != null) {
          receiveMove(msg['fen']);
        }
        // Update timers if needed
        notifyListeners();
        break;
        
      case 'GAME_OVER':
        _gameStatus = 'Game Over: ${msg['reason']} - Winner: ${msg['winner']}';
        notifyListeners();
        break;
        
      case 'PENDING_GAMES_UPDATE':
        _pendingGames = msg['games'];
        notifyListeners();
        break;
        
      case 'ERROR':
        print('Error from server: ${msg['message']}');
        break;
    }
  }

  void createGame(String timeControl, {bool isBot = false}) {
    if (_socket == null) return;
    
    _socket!.send({
      'type': 'INIT_GAME',
      'timeControl': timeControl,
      'isBot': isBot,
      'isPrivate': false,
      'botDifficulty': 1
    });
  }

  void joinGame(String gameId) {
    if (_socket == null) return;
    _socket!.send({
      'type': 'JOIN_GAME',
      'gameId': gameId
    });
  }
  
  void quickPlay() {
      if (_socket == null) return;
      _socket!.send({
          'type': 'QUICK_PLAY',
          'timeControl': '10+0', // Default
      });
  }

  void _onBoardChange() {
    if (_isServerUpdate) return;
    
    // User made a move
    try {
      final history = (controller as dynamic).game.history;
      if (history != null && history.isNotEmpty) {
        final lastMove = history.last;
        
        String from = lastMove.fromAlgebraic ?? lastMove.toString(); 
        String to = lastMove.toAlgebraic ?? "";
        
        // Ensure we strictly have 'from' and 'to'
        if (from.isNotEmpty && to.isNotEmpty) {
            makeMove(from, to);
        }
      }
    } catch (e) {
      // print("Error in _onBoardChange or parsing move: $e");
    }
  }

  void receiveMove(String fen) {
     _isServerUpdate = true;
     controller.loadFen(fen);
     _isServerUpdate = false;
  }

  void makeMove(String from, String to) {
    if (_socket == null || !_isInGame || _gameId == null) return;

    _socket!.send({
      'type': 'MOVE',
      'gameId': _gameId,
      'from': from,
      'to': to,
    });
  }
  
  void leaveGame() {
      _isInGame = false;
      _gameId = null;
      controller.resetBoard();
      notifyListeners();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    controller.removeListener(_onBoardChange);
    super.dispose();
  }
}
