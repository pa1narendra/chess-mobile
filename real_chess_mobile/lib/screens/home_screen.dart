import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../api/socket_service.dart';
import '../widgets/custom_button.dart';
import '../main.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasNavigatedToGame = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final game = Provider.of<GameProvider>(context, listen: false);

    // Initialize network service for offline detection
    game.initNetworkService();

    if (auth.token != null) {
      game.initSocket(auth.token!);
    }

    auth.onLogout = () {
      game.disconnectSocket();
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Consumer<GameProvider>(
      builder: (context, game, child) {
        // Automatically navigate to GameScreen if in game
        if (game.isInGame && !_hasNavigatedToGame) {
          _hasNavigatedToGame = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              ).then((_) {
                _hasNavigatedToGame = false;
              });
            }
          });
        } else if (!game.isInGame) {
          _hasNavigatedToGame = false;
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: AppColors.tealAccent, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Chessing'),
              ],
            ),
            actions: [
              // Connection indicator
              _buildConnectionBadge(game),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => _showLogoutConfirmation(context),
                tooltip: 'Logout',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Card
                _buildWelcomeCard(context, auth),
                const SizedBox(height: 32),

                // Play Section Title
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.tealAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Play',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Game Mode Cards
                GameModeCard(
                  title: game.isInQueue ? 'Searching...' : 'Quick Play',
                  subtitle: game.isInQueue
                      ? 'Looking for an opponent'
                      : 'Find an opponent instantly',
                  icon: game.isInQueue ? Icons.hourglass_top_rounded : Icons.flash_on_rounded,
                  gradient: [AppColors.amberWarning, const Color(0xFFEF4444)],
                  onTap: game.isInQueue
                      ? () => _showCancelQueueDialog(context, game)
                      : () => _showTimeControlDialog(context, game),
                  isLoading: game.isInQueue,
                ),
                const SizedBox(height: 12),

                GameModeCard(
                  title: 'Play vs Bot',
                  subtitle: 'Practice against AI',
                  icon: Icons.smart_toy_rounded,
                  gradient: [AppColors.electricBlue, AppColors.purpleAccent],
                  onTap: () => _showBotDifficultyDialog(context, game),
                ),
                const SizedBox(height: 12),

                GameModeCard(
                  title: 'Play with Friends',
                  subtitle: 'Create or join a private game',
                  icon: Icons.group_rounded,
                  gradient: [AppColors.tealAccent, AppColors.emeraldGreen],
                  onTap: () => _showPlayOptionsDialog(context, game),
                ),

                const SizedBox(height: 32),

                // Stats Section (if available)
                if (auth.user != null && auth.user!['gamesPlayed'] != null && auth.user!['gamesPlayed'] > 0)
                  _buildStatsSection(context, auth),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionBadge(GameProvider game) {
    Color color;
    String tooltip;

    switch (game.connectionState) {
      case SocketConnectionState.connected:
        color = AppColors.emeraldGreen;
        tooltip = 'Connected';
        break;
      case SocketConnectionState.connecting:
        color = AppColors.amberWarning;
        tooltip = 'Connecting...';
        break;
      case SocketConnectionState.reconnecting:
        color = AppColors.amberWarning;
        tooltip = 'Reconnecting...';
        break;
      case SocketConnectionState.disconnected:
        color = AppColors.roseError;
        tooltip = 'Disconnected';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              tooltip.replaceAll('...', ''),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context, AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.tealAccent, AppColors.electricBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                (auth.user?['username'] ?? 'P')[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  auth.user?['username'] ?? 'Player',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.tealAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.tealAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: AppColors.tealAccent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${auth.user?['rating'] ?? 1200}',
                  style: TextStyle(
                    color: AppColors.tealAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, AuthProvider auth) {
    final wins = auth.user?['wins'] ?? 0;
    final losses = auth.user?['losses'] ?? 0;
    final draws = auth.user?['draws'] ?? 0;
    final gamesPlayed = auth.user?['gamesPlayed'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.electricBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Your Stats',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Played', gamesPlayed.toString(), AppColors.electricBlue),
              _buildStatDivider(),
              _buildStatItem('Wins', wins.toString(), AppColors.emeraldGreen),
              _buildStatDivider(),
              _buildStatItem('Losses', losses.toString(), AppColors.roseError),
              _buildStatDivider(),
              _buildStatItem('Draws', draws.toString(), AppColors.amberWarning),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.borderColor,
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
            onPressed: () {
              Navigator.pop(ctx);
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showCancelQueueDialog(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Search?'),
        content: const Text('Stop looking for an opponent?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Searching'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseError),
            onPressed: () {
              game.cancelQueue();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showTimeControlDialog(BuildContext context, GameProvider game) {
    final timeControls = [
      {'minutes': 1, 'label': '1 min', 'subtitle': 'Bullet', 'color': AppColors.roseError},
      {'minutes': 3, 'label': '3 min', 'subtitle': 'Bullet', 'color': Colors.deepOrange},
      {'minutes': 5, 'label': '5 min', 'subtitle': 'Blitz', 'color': AppColors.amberWarning},
      {'minutes': 10, 'label': '10 min', 'subtitle': 'Rapid', 'color': AppColors.tealAccent},
      {'minutes': 15, 'label': '15 min', 'subtitle': 'Rapid', 'color': AppColors.electricBlue},
      {'minutes': 30, 'label': '30 min', 'subtitle': 'Classical', 'color': AppColors.purpleAccent},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.timer_rounded, color: AppColors.amberWarning),
            const SizedBox(width: 8),
            const Text('Select Time Control'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: timeControls.map((tc) {
              final color = tc['color'] as Color;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Center(
                      child: Text(
                        '${tc['minutes']}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Text(tc['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tc['subtitle'] as String, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(ctx);
                    game.quickPlay(timeControl: '${tc['minutes']}+0');
                  },
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showBotDifficultyDialog(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.smart_toy_rounded, color: AppColors.electricBlue),
            const SizedBox(width: 8),
            const Text('Select Difficulty'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Local play indicator
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.tealAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.tealAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt_rounded, color: AppColors.tealAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Plays locally - No internet needed',
                      style: TextStyle(color: AppColors.tealAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            _buildDifficultyOption(ctx, game, 1, 'Beginner', 'Perfect for learning', AppColors.emeraldGreen),
            _buildDifficultyOption(ctx, game, 2, 'Easy', 'Casual play', AppColors.tealAccent),
            _buildDifficultyOption(ctx, game, 3, 'Medium', 'A fair challenge', AppColors.amberWarning),
            _buildDifficultyOption(ctx, game, 4, 'Hard', 'For experienced players', Colors.deepOrange),
            _buildDifficultyOption(ctx, game, 5, 'Expert', 'Maximum difficulty', AppColors.roseError),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyOption(BuildContext context, GameProvider game, int level, String title, String subtitle, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Center(
            child: Text(
              '$level',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textMuted),
        onTap: () {
          Navigator.pop(context);
          // Always use local bot - no server needed
          game.startOfflineBotGame(level);
        },
      ),
    );
  }

  void _showPlayOptionsDialog(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.group_rounded, color: AppColors.tealAccent),
            const SizedBox(width: 8),
            const Text('Play with Friends'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.electricBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_circle_rounded, color: AppColors.electricBlue),
                ),
                title: const Text('Create New Game', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Get a code to share', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textMuted),
                onTap: () {
                  Navigator.pop(ctx);
                  game.createGame('10+0', isBot: false);
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.emeraldGreen.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.input_rounded, color: AppColors.emeraldGreen),
                ),
                title: const Text('Join Game', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Enter a game code', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textMuted),
                onTap: () {
                  Navigator.pop(ctx);
                  _showJoinGameDialog(context, game);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showJoinGameDialog(BuildContext context, GameProvider game) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.input_rounded, color: AppColors.emeraldGreen),
            const SizedBox(width: 8),
            const Text('Join Game'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the 6-digit game code shared by your friend',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 8),
              ),
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty && code.length == 6) {
                Navigator.pop(ctx);
                game.joinGame(code);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
