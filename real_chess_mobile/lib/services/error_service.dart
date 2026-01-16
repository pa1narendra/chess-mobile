class ErrorService {
  static String getUserFriendlyMessage(String? error) {
    if (error == null || error.isEmpty) {
      return 'An unexpected error occurred. Please try again.';
    }

    final lowerError = error.toLowerCase();

    // Connection errors
    if (lowerError.contains('socket') || lowerError.contains('connection')) {
      return 'Unable to connect to server. Please check your internet connection.';
    }

    if (lowerError.contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }

    // Authentication errors
    if (lowerError.contains('unauthorized') || lowerError.contains('401')) {
      return 'Session expired. Please log in again.';
    }

    if (lowerError.contains('invalid token') || lowerError.contains('jwt')) {
      return 'Session expired. Please log in again.';
    }

    if (lowerError.contains('invalid credentials') || lowerError.contains('wrong password')) {
      return 'Invalid email or password. Please try again.';
    }

    if (lowerError.contains('user not found')) {
      return 'Account not found. Please check your email or register.';
    }

    if (lowerError.contains('email already') || lowerError.contains('user already')) {
      return 'An account with this email already exists.';
    }

    // Game errors
    if (lowerError.contains('game not found')) {
      return 'Game not found. It may have ended or the code is invalid.';
    }

    if (lowerError.contains('game full')) {
      return 'This game already has two players.';
    }

    if (lowerError.contains('not your turn')) {
      return 'Please wait for your turn.';
    }

    if (lowerError.contains('invalid move')) {
      return 'That move is not allowed.';
    }

    if (lowerError.contains('game over') || lowerError.contains('game ended')) {
      return 'This game has already ended.';
    }

    // Queue errors
    if (lowerError.contains('queue') && lowerError.contains('timeout')) {
      return 'No opponent found. Please try again.';
    }

    if (lowerError.contains('already in queue')) {
      return 'You are already looking for a match.';
    }

    // Bot errors
    if (lowerError.contains('stockfish') || lowerError.contains('engine')) {
      return 'Chess engine error. Please restart the game.';
    }

    if (lowerError.contains('bot') && lowerError.contains('thinking')) {
      return 'Bot is still thinking. Please wait.';
    }

    // Network errors
    if (lowerError.contains('network') || lowerError.contains('internet')) {
      return 'No internet connection. Please check your network.';
    }

    // Server errors
    if (lowerError.contains('500') || lowerError.contains('server error')) {
      return 'Server error. Please try again later.';
    }

    if (lowerError.contains('503') || lowerError.contains('service unavailable')) {
      return 'Server is temporarily unavailable. Please try again later.';
    }

    // Return original if no match (but clean it up)
    if (error.length > 100) {
      return 'An error occurred. Please try again.';
    }

    return error;
  }

  static String getConnectionMessage(bool isConnected, bool isReconnecting) {
    if (isConnected) {
      return 'Connected';
    } else if (isReconnecting) {
      return 'Reconnecting...';
    } else {
      return 'Disconnected';
    }
  }
}
