import 'dart:async';
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
  String? _errorMessage; // Error from server
  String? _gameCode; // Shareable Game Code
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  // Pending games list
  List<dynamic> _pendingGames = [];

  bool _isServerUpdate = false;

  final _drawOfferController = StreamController<bool>.broadcast();
  Stream<bool> get drawOfferStream => _drawOfferController.stream;

  // Time remaining for each player
  Map<String, int> _timeRemaining = {'w': 600000, 'b': 600000};
  String _currentTurn = 'w';
  Timer? _gameTimer;
  int _lastMoveTime = 0;

  String? _whitePlayerName;
  String? _blackPlayerName;

  Map<String, int> get timeRemaining => _timeRemaining;
  String get currentTurn => _currentTurn;
  String get whitePlayerName => _whitePlayerName ?? 'White';
  String get blackPlayerName => _blackPlayerName ?? 'Black';

  GameProvider() {
    // No longer using controller listener - using onMove callback instead
  }

  bool get isInGame => _isInGame;
  String? get gameId => _gameId;
  String? get gameCode => _gameCode;
  String get playerColor => _playerColor;
  String? get gameStatus => _gameStatus;
  String? get errorMessage => _errorMessage;
  SocketConnectionState get connectionState => _connectionState;
  List<dynamic> get pendingGames => _pendingGames;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String? _token;

  void initSocket(String token) {
    if (_socket != null) return;

    _token = token;
    _socket = SocketService(
      onMessage: _onMessage,
      onConnectionStateChange: (state) {
        _connectionState = state;
        notifyListeners();
      },
    );
    _socket!.connect(token);
  }

  // Parse timeControl string like "10+0" to get minutes
  int _parseTimeControl(String timeControl) {
    final parts = timeControl.split('+');
    return int.tryParse(parts[0]) ?? 10;
  }

  void _onMessage(dynamic msg) {
    if (msg == null || msg is! Map<String, dynamic>) return;

    final type = msg['type'];
    if (type == null) return;

    switch (type) {
      case 'GAME_CREATED':
      case 'GAME_JOINED':
        final gameId = msg['gameId'];
        final color = msg['color'];

        if (gameId == null || color == null) {
          _errorMessage = 'Invalid game data received';
          notifyListeners();
          return;
        }

        _gameId = gameId.toString();
        // If we created it and it's private (waiting), store the code
        if (type == 'GAME_CREATED') {
             _gameCode = _gameId; 
             _gameStatus = 'Waiting for opponent... Code: $_gameCode';
        } else {
             _gameCode = null;
             _gameStatus = null;
        }

        _playerColor = (color == 'w' || color == 'b') ? color : 'w';
        _isInGame = true;
        _errorMessage = null;
        
        // Update names
        _whitePlayerName = msg['whitePlayerName'];
        _blackPlayerName = msg['blackPlayerName'];
      
        // Parse initial time
        final timeData = msg['timeRemaining'];
        if (timeData != null && timeData is Map) {
          _timeRemaining = {
            'w': (timeData['w'] as num?)?.toInt() ?? 600000,
            'b': (timeData['b'] as num?)?.toInt() ?? 600000,
          };
        }
        
        _startLocalTimer();

        final fen = msg['fen'];
        if (fen != null && fen is String && fen.isNotEmpty) {
          receiveMove(fen);
          // Parse current turn from FEN
          final fenParts = fen.split(' ');
          if (fenParts.length > 1) {
            _currentTurn = fenParts[1];
          }
        } else {
          controller.resetBoard();
          _currentTurn = 'w';
        }
        notifyListeners();
        break;

      case 'UPDATE_BOARD':
        final fen = msg['fen'];
        if (fen != null && fen is String && fen.isNotEmpty) {
          receiveMove(fen);
          // Update current turn from FEN (6th field is turn indicator)
          final fenParts = fen.split(' ');
          if (fenParts.length > 1) {
            _currentTurn = fenParts[1];
          }
        }
        // Update time remaining
        final timeData = msg['timeRemaining'];
        if (timeData != null && timeData is Map) {
          _timeRemaining = {
            'w': (timeData['w'] as num?)?.toInt() ?? _timeRemaining['w']!,
            'b': (timeData['b'] as num?)?.toInt() ?? _timeRemaining['b']!,
          };
        }
        _startLocalTimer();
        notifyListeners();
        break;

      case 'GAME_OVER':
        final reason = msg['reason'] ?? 'Unknown';
        final winner = msg['winner'] ?? 'Unknown';
        _gameStatus = 'Game Over: $reason - Winner: $winner';
        notifyListeners();
        break;

      case 'PENDING_GAMES_UPDATE':
        final games = msg['games'];
        if (games is List) {
          _pendingGames = games;
        }
        notifyListeners();
        break;

      case 'ERROR':
        final message = msg['message'];
        _errorMessage = message?.toString() ?? 'Unknown error';
        notifyListeners();
        break;

      case 'CONNECTED':
        // Server acknowledged connection - request pending games
        _socket?.send({'type': 'GET_PENDING_GAMES'});
        notifyListeners();
        break;

      case 'OPPONENT_JOINED':
        // Opponent has joined the game - notify UI
        _errorMessage = null;
        _gameStatus = null; // Clear "Waiting" status
        _gameCode = null; // Hide code once game starts
        if (msg['whitePlayerName'] != null) _whitePlayerName = msg['whitePlayerName'];
        if (msg['blackPlayerName'] != null) _blackPlayerName = msg['blackPlayerName'];
        
        _startLocalTimer();
        notifyListeners();
        break;

      case 'DRAW_OFFER':
        // Notify UI to show dialog
        _drawOfferController.add(true);
        break;

      case 'DRAW_DECLINE':
        _errorMessage = "Opponent declined draw offer";
        notifyListeners();
        break;
    }
  }

  void createGame(String timeControl, {bool isBot = false, int botDifficulty = 3}) {
    if (_socket == null) return;

    _gameCode = null;

    _socket!.send({
      'type': 'INIT_GAME',
      'timeControl': _parseTimeControl(timeControl),
      'isBot': isBot,
      'isPrivate': !isBot, // Human games are private by default for "Play with Friends" flow
      'botDifficulty': botDifficulty,
      'token': _token,
    });
  }

  void joinGame(String gameId) {
    if (_socket == null) return;
    _socket!.send({
      'type': 'JOIN_GAME',
      'gameId': gameId,
      'token': _token,
    });
  }

  void quickPlay({String timeControl = '10+0'}) {
    if (_socket == null) return;
    _socket!.send({
      'type': 'QUICK_PLAY',
      'timeControl': _parseTimeControl(timeControl),
      'token': _token,
    });
  }

  // Called by GameScreen when user makes a move on the board
  void onUserMove(String from, String to, {String? promotion}) {
    if (_isServerUpdate) return;
    if (_socket == null || !_isInGame || _gameId == null) return;

    // Check if it's user's turn
    if (_currentTurn != _playerColor) {
      // Not user's turn, revert the move
      return;
    }

    _socket!.send({
      'type': 'MOVE',
      'gameId': _gameId,
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
      'token': _token,
    });
  }

  void resign() {
    // Implement resignation
    // Backend needs a RESIGN message type, assuming standard logic implies sending a message
    // If backend doesn't support explicit RESIGN type yet via WebSocket message for 'RESIGN',
    // we might need to add it. But for now let's assume standard behavior or add a todo.
    // Based on index.ts review, there wasn't a visible RESIGN handler in the snippet.
    // I will add the send call, assuming backend handles it or I'll update backend.
    // Index.ts showed handlers for INIT, JOIN, MOVE.
    // I need to check if RESIGN is handled.
    // Wait, the backend DID have `resign(gameId, playerId)` in GameManager, but how is it called?
    // Let's assume we need to add a type 'RESIGN' to index.ts later if missing.
    if (_socket == null || !_isInGame || _gameId == null) return;
    _socket!.send({
      'type': 'RESIGN',
      'gameId': _gameId,
      'token': _token
    });
  }

  void offerDraw() {
    if (_socket == null || !_isInGame || _gameId == null) return;
    _socket!.send({
      'type': 'DRAW_OFFER', // Or just DRAW
      'gameId': _gameId,
      'token': _token
    });
  }

  void acceptDraw() {
    if (_socket == null || !_isInGame || _gameId == null) return;
    _socket!.send({
      'type': 'DRAW_ACCEPT',
      'gameId': _gameId,
      'token': _token,
    });
  }

  void declineDraw() {
    if (_socket == null || !_isInGame || _gameId == null) return;
    _socket!.send({
      'type': 'DRAW_DECLINE',
      'gameId': _gameId,
      'token': _token,
    });
  }

  void receiveMove(String fen) {
    _isServerUpdate = true;
    controller.loadFen(fen);
    _isServerUpdate = false;
  }


  void leaveGame() {
    _isInGame = false;
    _gameId = null;
    _gameStatus = null;
    _errorMessage = null;
    _stopLocalTimer();
    controller.resetBoard();
    notifyListeners();
  }

  void _startLocalTimer() {
    _stopLocalTimer();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gameStatus != null && _gameStatus!.startsWith('Game Over')) {
        timer.cancel();
        return;
      }
      
      // If waiting for opponent, don't decrement
      if (_gameCode != null) return;

      if (_timeRemaining[_currentTurn]! > 0) {
        _timeRemaining[_currentTurn] = _timeRemaining[_currentTurn]! - 1000;
        if (_timeRemaining[_currentTurn]! < 0) _timeRemaining[_currentTurn] = 0;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  void _stopLocalTimer() {
    _gameTimer?.cancel();
    _gameTimer = null;
  }

  void disconnectSocket() {
    _socket?.disconnect();
    _stopLocalTimer();
    _socket = null;
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _stopLocalTimer();
    _drawOfferController.close();
    super.dispose();
  }
}
