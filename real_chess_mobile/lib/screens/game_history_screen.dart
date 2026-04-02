import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../api/api_service.dart';
import 'game_detail_screen.dart';
import '../main.dart';

class GameHistoryScreen extends StatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  State<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends State<GameHistoryScreen> {
  List<dynamic> _games = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGames();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _page < _totalPages) {
        _loadMore();
      }
    }
  }

  Future<void> _loadGames() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.getGameHistory(token, page: 1);
      setState(() {
        _games = result['data'] ?? [];
        _page = 1;
        _totalPages = result['pagination']?['totalPages'] ?? 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final result = await ApiService.getGameHistory(token, page: _page + 1);
      setState(() {
        _games.addAll(result['data'] ?? []);
        _page++;
        _isLoadingMore = false;
      });
    } catch (_) {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Game History', style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: AppColors.roseError, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _loadGames, child: const Text('Retry')),
                    ],
                  ),
                )
              : _games.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, color: AppColors.textMuted, size: 64),
                          SizedBox(height: 16),
                          Text('No games played yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                          SizedBox(height: 8),
                          Text('Your game history will appear here', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadGames,
                      color: AppColors.tealAccent,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _games.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _games.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: AppColors.tealAccent, strokeWidth: 2),
                              ),
                            );
                          }
                          return _buildGameCard(_games[index]);
                        },
                      ),
                    ),
    );
  }

  Widget _buildGameCard(Map<String, dynamic> game) {
    final result = game['result'] as String? ?? 'unknown';
    final reason = game['reason'] as String? ?? '';
    final opponentName = game['opponentName'] as String? ?? 'Unknown';
    final isBot = game['isBot'] == true;
    final movesCount = game['movesCount'] ?? 0;
    final playerColor = game['playerColor'] as String? ?? 'w';
    final endedAt = game['endedAt'] != null ? DateTime.tryParse(game['endedAt']) : null;
    final accuracy = game['accuracy'];

    Color resultColor;
    String resultText;
    IconData resultIcon;

    switch (result) {
      case 'win':
        resultColor = AppColors.emeraldGreen;
        resultText = 'Victory';
        resultIcon = Icons.emoji_events;
        break;
      case 'loss':
        resultColor = AppColors.roseError;
        resultText = 'Defeat';
        resultIcon = Icons.close;
        break;
      case 'draw':
        resultColor = AppColors.amberWarning;
        resultText = 'Draw';
        resultIcon = Icons.handshake;
        break;
      default:
        resultColor = AppColors.textMuted;
        resultText = 'Unknown';
        resultIcon = Icons.help_outline;
    }

    final gameId = game['gameId'] as String?;

    return GestureDetector(
      onTap: gameId != null ? () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GameDetailScreen(gameId: gameId),
        ));
      } : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Result indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(resultIcon, color: resultColor, size: 24),
            ),
            const SizedBox(width: 14),
            // Game info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        resultText,
                        style: TextStyle(color: resultColor, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'vs $opponentName',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      ),
                      if (isBot) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.purpleAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('BOT', style: TextStyle(color: AppColors.purpleAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        playerColor == 'w' ? Icons.circle : Icons.circle_outlined,
                        color: playerColor == 'w' ? Colors.white : AppColors.textMuted,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$reason  |  $movesCount moves',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      if (accuracy != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${accuracy[playerColor]}% accuracy',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Date
            if (endedAt != null)
              Text(
                DateFormat('MMM d').format(endedAt),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
          ],
        ),
      ),
    ),
    );
  }
}
