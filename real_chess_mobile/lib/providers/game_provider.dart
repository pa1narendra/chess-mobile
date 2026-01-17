import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/socket_service.dart';
import '../services/bot_service.dart';
import '../services/network_service.dart';
import '../services/error_service.dart';

const String _activeGameKey = 'active_game_id';
const String _playerColorKey = 'player_color';

class GameProvider with ChangeNotifier {
  SocketService? _socket;
  ChessBoardController controller = ChessBoardController();

  // Offline bot services
  final LocalBotService _localBot = LocalBotService();
  final NetworkService _networkService = NetworkService();

  String? _gameId;
  String _playerColor = 'w'; // 'w' or 'b'

  bool _isInGame = false;
  String? _gameStatus; // 'Checkmate', 'Draw', etc.
  String? _errorMessage; // Error from server
  String? _gameCode; // Shareable Game Code
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  // Queue state
  bool _isInQueue = false;
  String? _queueMessage;

  // Offline game state
  bool _isOfflineGame = false;
  bool _isUntimedGame = false;
  BotDifficulty? _currentBotDifficulty;
  chess_lib.Chess? _offlineChess;

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

  // Opponent disconnection state
  bool _opponentDisconnected = false;
  String? _disconnectionMessage;

  // Tap-to-move state
  String? _selectedSquare;
  List<String> _legalMoves = [];
  List<String> _captureMoves = []; // Squares where captures can be made

  Map<String, int> get timeRemaining => _timeRemaining;
  String get currentTurn => _currentTurn;
  String get whitePlayerName => _whitePlayerName ?? 'White';
  String get blackPlayerName => _blackPlayerName ?? 'Black';
  bool get opponentDisconnected => _opponentDisconnected;
  String? get disconnectionMessage => _disconnectionMessage;
  String? get selectedSquare => _selectedSquare;
  List<String> get legalMoves => _legalMoves;
  List<String> get captureMoves => _captureMoves;

  GameProvider() {
    // No longer using controller listener - using onMove callback instead
  }

  // Game state persistence methods
  Future<void> _saveActiveGame() async {
    if (_gameId != null && !_isOfflineGame) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeGameKey, _gameId!);
      await prefs.setString(_playerColorKey, _playerColor);
      debugPrint('[GameProvider] Saved active game: $_gameId, color: $_playerColor');
    }
  }

  Future<void> _clearActiveGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeGameKey);
    await prefs.remove(_playerColorKey);
    debugPrint('[GameProvider] Cleared active game');
  }

  Future<Map<String, String>?> _loadActiveGame() async {
    final prefs = await SharedPreferences.getInstance();
    final gameId = prefs.getString(_activeGameKey);
    final color = prefs.getString(_playerColorKey);
    if (gameId != null && color != null) {
      debugPrint('[GameProvider] Loaded active game: $gameId, color: $color');
      return {'gameId': gameId, 'color': color};
    }
    return null;
  }

  // Try to rejoin active game on connection
  Future<void> tryRejoinGame() async {
    if (_socket == null || _isOfflineGame) return;

    final savedGame = await _loadActiveGame();
    if (savedGame != null) {
      debugPrint('[GameProvider] Attempting to rejoin game: ${savedGame['gameId']}');
      _socket!.send({
        'type': 'REJOIN_GAME',
        'token': _token,
      });
    }
  }

  bool get isInGame => _isInGame;
  String? get gameId => _gameId;
  String? get gameCode => _gameCode;
  String get playerColor => _playerColor;
  String? get gameStatus => _gameStatus;
  String? get errorMessage => _errorMessage;
  SocketConnectionState get connectionState => _connectionState;
  List<dynamic> get pendingGames => _pendingGames;
  bool get isInQueue => _isInQueue;
  String? get queueMessage => _queueMessage;
  bool get isOfflineGame => _isOfflineGame;
  bool get isUntimedGame => _isUntimedGame;
  bool get isOnline => _networkService.isOnline;

  Future<void> initNetworkService() async {
    await _networkService.initialize();
    _networkService.onStatusChange.listen((isOnline) {
      notifyListeners();
    });
  }

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
             final isPrivate = msg['isPrivate'] == true;
             if (isPrivate) {
                _gameStatus = 'Waiting for opponent... Code: $_gameCode';
             } else {
                _gameStatus = 'Searching for opponent...';
             }
        } else {
             _gameCode = null;
             _gameStatus = null;
        }

        _playerColor = (color == 'w' || color == 'b') ? color : 'w';
        _isInGame = true;
        _errorMessage = null;
        _opponentDisconnected = false;
        _disconnectionMessage = null;

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

        // Save active game for persistence
        _saveActiveGame();
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
        _opponentDisconnected = false;
        _disconnectionMessage = null;
        // Clear saved game since it's over
        _clearActiveGame();
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
        _errorMessage = ErrorService.getUserFriendlyMessage(message?.toString());
        notifyListeners();
        break;

      case 'CONNECTED':
        // Server acknowledged connection - request pending games
        _socket?.send({'type': 'GET_PENDING_GAMES'});
        // Try to rejoin any active game
        tryRejoinGame();
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

      case 'QUEUE_STATUS':
        _isInQueue = true;
        _queueMessage = msg['message'] ?? 'Looking for opponent...';
        notifyListeners();
        break;

      case 'MATCH_FOUND':
        _isInQueue = false;
        _queueMessage = null;

        final gameId = msg['gameId'];
        final color = msg['color'];

        if (gameId != null && color != null) {
          _gameId = gameId.toString();
          _playerColor = (color == 'w' || color == 'b') ? color : 'w';
          _isInGame = true;
          _errorMessage = null;
          _gameStatus = null;
          _gameCode = null;
          _opponentDisconnected = false;
          _disconnectionMessage = null;

          _whitePlayerName = msg['whitePlayerName'];
          _blackPlayerName = msg['blackPlayerName'];

          final timeData = msg['timeRemaining'];
          if (timeData != null && timeData is Map) {
            _timeRemaining = {
              'w': (timeData['w'] as num?)?.toInt() ?? 600000,
              'b': (timeData['b'] as num?)?.toInt() ?? 600000,
            };
          }

          final fen = msg['fen'];
          if (fen != null && fen is String && fen.isNotEmpty) {
            receiveMove(fen);
            final fenParts = fen.split(' ');
            if (fenParts.length > 1) {
              _currentTurn = fenParts[1];
            }
          } else {
            controller.resetBoard();
            _currentTurn = 'w';
          }

          _startLocalTimer();

          // Subscribe to game room to receive move updates
          _socket?.send({
            'type': 'SUBSCRIBE_GAME',
            'gameId': gameId,
          });

          // Save active game for persistence
          _saveActiveGame();
        }
        notifyListeners();
        break;

      case 'QUEUE_TIMEOUT':
        _isInQueue = false;
        _queueMessage = null;
        _errorMessage = ErrorService.getUserFriendlyMessage(msg['message'] ?? 'queue timeout');
        notifyListeners();
        break;

      case 'QUEUE_CANCELLED':
        _isInQueue = false;
        _queueMessage = null;
        notifyListeners();
        break;

      case 'REJOIN_SUCCESS':
        final gameId = msg['gameId'];
        final color = msg['color'];

        if (gameId != null && color != null) {
          _gameId = gameId.toString();
          _playerColor = (color == 'w' || color == 'b') ? color : 'w';
          _isInGame = true;
          _errorMessage = null;
          _gameStatus = null;
          _gameCode = null;
          _opponentDisconnected = msg['opponentDisconnected'] == true;
          if (_opponentDisconnected) {
            _disconnectionMessage = 'Opponent is disconnected. Waiting for them to reconnect...';
          }

          _whitePlayerName = msg['whitePlayerName'];
          _blackPlayerName = msg['blackPlayerName'];

          final timeData = msg['timeRemaining'];
          if (timeData != null && timeData is Map) {
            _timeRemaining = {
              'w': (timeData['w'] as num?)?.toInt() ?? 600000,
              'b': (timeData['b'] as num?)?.toInt() ?? 600000,
            };
          }

          final fen = msg['fen'];
          if (fen != null && fen is String && fen.isNotEmpty) {
            receiveMove(fen);
            final fenParts = fen.split(' ');
            if (fenParts.length > 1) {
              _currentTurn = fenParts[1];
            }
          } else {
            controller.resetBoard();
            _currentTurn = 'w';
          }

          _startLocalTimer();
          debugPrint('[GameProvider] Rejoined game: $_gameId, color: $_playerColor');
        }
        notifyListeners();
        break;

      case 'REJOIN_FAILED':
        // No active game to rejoin - clear saved state
        _clearActiveGame();
        debugPrint('[GameProvider] Rejoin failed: ${msg['message']}');
        break;

      case 'OPPONENT_DISCONNECTED':
        _opponentDisconnected = true;
        _disconnectionMessage = msg['message'] ?? 'Opponent disconnected. Waiting for reconnect...';
        notifyListeners();
        break;

      case 'OPPONENT_RECONNECTED':
        _opponentDisconnected = false;
        _disconnectionMessage = null;
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

    _isInQueue = true;
    _queueMessage = 'Looking for opponent...';
    notifyListeners();

    _socket!.send({
      'type': 'QUICK_PLAY',
      'timeControl': _parseTimeControl(timeControl),
      'token': _token,
    });
  }

  void cancelQueue() {
    if (_socket == null) return;
    _socket!.send({'type': 'CANCEL_QUEUE'});
    _isInQueue = false;
    _queueMessage = null;
    notifyListeners();
  }

  // Called by GameScreen when user makes a move on the board
  void onUserMove(String from, String to, {String? promotion}) {
    // Clear selection
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];

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

  // Tap-to-move methods
  void selectSquare(String square) {
    // Get the chess instance for validation
    chess_lib.Chess? chess;
    if (_isOfflineGame && _offlineChess != null) {
      chess = _offlineChess;
    } else {
      // For online games, create a temporary chess instance from current FEN
      final fen = controller.getFen();
      chess = chess_lib.Chess.fromFEN(fen);
    }

    if (chess == null) return;

    // Check if it's the player's turn
    final currentTurnColor = chess.turn == chess_lib.Color.WHITE ? 'w' : 'b';
    if (currentTurnColor != _playerColor) return;

    // Check if the square has a piece of the current player
    final piece = chess.get(square);
    if (piece != null) {
      final pieceColor = piece.color == chess_lib.Color.WHITE ? 'w' : 'b';
      if (pieceColor == _playerColor) {
        // Select this square and calculate legal moves
        _selectedSquare = square;
        final (moves, captures) = _calculateLegalMoves(chess, square);
        _legalMoves = moves;
        _captureMoves = captures;
        notifyListeners();
        return;
      }
    }

    // If we have a selected square and tapped on a legal move destination
    if (_selectedSquare != null && _legalMoves.contains(square)) {
      _makeTapMove(_selectedSquare!, square);
      return;
    }

    // Clear selection if tapped on empty or opponent's piece
    clearSelection();
  }

  (List<String>, List<String>) _calculateLegalMoves(chess_lib.Chess chess, String fromSquare) {
    final moves = chess.moves({'square': fromSquare, 'verbose': true});
    final destinations = <String>[];
    final captures = <String>[];
    for (final move in moves) {
      if (move is Map && move['to'] != null) {
        final to = move['to'] as String;
        destinations.add(to);
        // Check if this is a capture move
        if (move['captured'] != null) {
          captures.add(to);
        }
      }
    }
    return (destinations, captures);
  }

  void clearSelection() {
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];
    _captureMoves = [];
    notifyListeners();
  }

  void _makeTapMove(String from, String to) {
    // Clear selection first
    final fromSquare = from;
    final toSquare = to;
    clearSelection();

    // Make the move using the existing controller
    // The ChessBoard widget handles promotion dialogs automatically
    try {
      controller.makeMove(from: fromSquare, to: toSquare);
      // The onMove callback in GameScreen will handle sending to server
    } catch (e) {
      debugPrint('Error making tap move: $e');
    }
  }

  void resign() {
    // Handle offline game resignation
    if (_isOfflineGame) {
      _gameStatus = 'Game Over: You resigned';
      _stopLocalTimer();
      _selectedSquare = null;
      _legalMoves = [];
      _captureMoves = [];
      notifyListeners();
      return;
    }

    // Handle online game resignation
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
    // Clear selection when receiving a move
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];
  }


  void leaveGame() {
    _isInGame = false;
    _isUntimedGame = false;
    _gameId = null;
    _gameStatus = null;
    _errorMessage = null;
    _opponentDisconnected = false;
    _disconnectionMessage = null;
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];
    _stopLocalTimer();
    controller.resetBoard();
    // Clear saved game when explicitly leaving
    _clearActiveGame();
    notifyListeners();
  }

  void _startLocalTimer() {
    _stopLocalTimer();

    // Don't start timer for untimed games
    if (_isUntimedGame) return;

    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gameStatus != null && _gameStatus!.startsWith('Game Over')) {
        timer.cancel();
        return;
      }

      // If waiting for opponent, don't decrement
      if (_gameCode != null && !_isOfflineGame) return;

      if (_timeRemaining[_currentTurn]! > 0) {
        _timeRemaining[_currentTurn] = _timeRemaining[_currentTurn]! - 1000;
        if (_timeRemaining[_currentTurn]! <= 0) {
          _timeRemaining[_currentTurn] = 0;
          // Timeout - game over
          _handleTimeout();
          timer.cancel();
        }
        notifyListeners();
      } else {
        // Time already at 0
        _handleTimeout();
        timer.cancel();
      }
    });
  }

  void _handleTimeout() {
    final loser = _currentTurn;
    final winner = loser == 'w' ? 'b' : 'w';

    if (_isOfflineGame) {
      // Offline game timeout
      if (loser == _playerColor) {
        _gameStatus = 'Game Over: You lost on time!';
      } else {
        _gameStatus = 'Game Over: You won on time!';
      }
    } else {
      // Online game timeout
      _gameStatus = 'Game Over: ${winner == 'w' ? 'White' : 'Black'} wins on time!';
    }

    _isInGame = false;
    debugPrint('[Timer] Timeout! $loser ran out of time. Game status: $_gameStatus');
    notifyListeners();
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

  // Offline Bot Game Methods
  Future<void> startOfflineBotGame(int difficulty) async {
    debugPrint('[Bot] Starting offline bot game with difficulty $difficulty');
    try {
      await _localBot.initialize();
      debugPrint('[Bot] Local bot initialized');

      _isOfflineGame = true;
      _isUntimedGame = true; // Bot games are untimed
      _isInGame = true;
      _playerColor = 'w';
      _currentTurn = 'w';
      _currentBotDifficulty = BotDifficulty.fromLevel(difficulty);
      _gameStatus = null;
      _errorMessage = null;
      _gameCode = null;
      _gameId = 'offline_${DateTime.now().millisecondsSinceEpoch}';

      // Initialize offline chess instance
      _offlineChess = chess_lib.Chess();
      debugPrint('[Bot] Chess instance created, FEN: ${_offlineChess!.fen}');

      // Reset board
      controller.resetBoard();

      // Bot games are untimed - set time to -1 to indicate no timer
      _timeRemaining = {'w': -1, 'b': -1};
      // Don't start timer for untimed games

      // Set names
      _whitePlayerName = 'You';
      _blackPlayerName = 'Bot (${_currentBotDifficulty!.displayName})';

      debugPrint('[Bot] Game started successfully, isInGame: $_isInGame, isOfflineGame: $_isOfflineGame, untimed: $_isUntimedGame');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[Bot] Error starting game: $e');
      debugPrint('[Bot] Stack trace: $stackTrace');
      _errorMessage = ErrorService.getUserFriendlyMessage('engine $e');
      notifyListeners();
    }
  }

  Future<void> onUserMoveOffline(String from, String to, {String? promotion}) async {
    debugPrint('[Bot] onUserMoveOffline called: $from -> $to, promotion: $promotion');
    debugPrint('[Bot] isOfflineGame: $_isOfflineGame, offlineChess: ${_offlineChess != null}, currentTurn: $_currentTurn, playerColor: $_playerColor');

    // Clear selection
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];

    if (!_isOfflineGame || _offlineChess == null) {
      debugPrint('[Bot] Move rejected - not in offline game');
      return;
    }

    try {
      // Sync _offlineChess with the controller's state
      // The ChessBoard widget already made the move on its internal engine
      final currentFen = controller.getFen();
      debugPrint('[Bot] Controller FEN after move: $currentFen');

      // Update our offline chess instance to match the controller
      _offlineChess = chess_lib.Chess.fromFEN(currentFen);
      _currentTurn = _offlineChess!.turn == chess_lib.Color.WHITE ? 'w' : 'b';

      debugPrint('[Bot] Synced _offlineChess, currentTurn: $_currentTurn');
      notifyListeners();

      // Check for game over
      if (_checkGameOver()) return;

      // Bot's turn
      await _makeBotMove();
    } catch (e) {
      _errorMessage = ErrorService.getUserFriendlyMessage('invalid move $e');
      notifyListeners();
    }
  }

  Future<void> _makeBotMove() async {
    debugPrint('[Bot] _makeBotMove called');
    debugPrint('[Bot] isOfflineGame: $_isOfflineGame, difficulty: $_currentBotDifficulty, chess: ${_offlineChess != null}');

    if (!_isOfflineGame || _currentBotDifficulty == null || _offlineChess == null) {
      debugPrint('[Bot] _makeBotMove aborted - conditions not met');
      return;
    }

    try {
      debugPrint('[Bot] Thinking... FEN: ${_offlineChess!.fen}');

      // Small delay to feel natural
      await Future.delayed(const Duration(milliseconds: 500));

      final fen = _offlineChess!.fen;
      final bestMove = await _localBot.getBestMove(fen, _currentBotDifficulty!);
      debugPrint('[Bot] Best move calculated: $bestMove');

      // Parse UCI move (e2e4)
      final from = bestMove.substring(0, 2);
      final to = bestMove.substring(2, 4);
      final promotion = bestMove.length > 4 ? bestMove.substring(4, 5) : null;

      debugPrint('[Bot] Making move: $from -> $to, promotion: $promotion');

      // Make bot move
      _offlineChess!.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });

      debugPrint('[Bot] Move made, new FEN: ${_offlineChess!.fen}');

      // Update controller display
      controller.loadFen(_offlineChess!.fen);

      _currentTurn = _offlineChess!.turn == chess_lib.Color.WHITE ? 'w' : 'b';
      debugPrint('[Bot] Turn updated to: $_currentTurn');
      notifyListeners();

      _checkGameOver();
    } catch (e, stackTrace) {
      debugPrint('[Bot] Error in _makeBotMove: $e');
      debugPrint('[Bot] Stack: $stackTrace');
      _errorMessage = ErrorService.getUserFriendlyMessage('bot $e');
      notifyListeners();
    }
  }

  bool _checkGameOver() {
    if (_offlineChess == null) return false;

    if (_offlineChess!.game_over) {
      if (_offlineChess!.in_checkmate) {
        final winner = _offlineChess!.turn == chess_lib.Color.WHITE ? 'Black' : 'White';
        _gameStatus = 'Game Over: Checkmate - $winner wins!';
      } else if (_offlineChess!.in_draw) {
        _gameStatus = 'Game Over: Draw';
      } else if (_offlineChess!.in_stalemate) {
        _gameStatus = 'Game Over: Stalemate';
      } else if (_offlineChess!.insufficient_material) {
        _gameStatus = 'Game Over: Draw - Insufficient material';
      } else if (_offlineChess!.in_threefold_repetition) {
        _gameStatus = 'Game Over: Draw - Threefold repetition';
      }

      _stopLocalTimer();
      notifyListeners();
      return true;
    }

    return false;
  }

  void stopOfflineGame() {
    _isOfflineGame = false;
    _isUntimedGame = false;
    _offlineChess = null;
    _currentBotDifficulty = null;
    _selectedSquare = null;
    _legalMoves = [];
    _captureMoves = [];
    _localBot.stopThinking();
    leaveGame();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _stopLocalTimer();
    _drawOfferController.close();
    _localBot.dispose();
    _networkService.dispose();
    super.dispose();
  }
}
