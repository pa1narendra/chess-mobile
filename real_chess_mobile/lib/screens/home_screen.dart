import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/custom_button.dart';
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
    // Connect socket when Home loads
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final game = Provider.of<GameProvider>(context, listen: false);

    if (auth.token != null) {
      game.initSocket(auth.token!);
    }

    // Set up logout callback to disconnect socket
    auth.onLogout = () {
      game.disconnectSocket();
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        // Automatically navigate to GameScreen if in game (only once)
        if (game.isInGame && !_hasNavigatedToGame) {
          _hasNavigatedToGame = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              ).then((_) {
                // Reset flag when returning from GameScreen
                _hasNavigatedToGame = false;
              });
            }
          });
        } else if (!game.isInGame) {
          // Reset flag when game ends
          _hasNavigatedToGame = false;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Real Chess'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout(),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome
                Text(
                  'Welcome, ${Provider.of<AuthProvider>(context).user?['username'] ?? 'Player'}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),

                // Main Actions
                _buildActionButton(
                  context,
                  'Quick Play',
                  Icons.flash_on,
                  Colors.amber,
                  () => game.quickPlay(),
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  context,
                  'Play vs Bot',
                  Icons.smart_toy,
                  Colors.purple,
                  () => _showBotDifficultyDialog(context, game),
                ),
                 const SizedBox(height: 16),
                _buildActionButton(
                  context,
                  'Play with Friends',
                  Icons.group,
                  Colors.blue,
                  () => _showPlayOptionsDialog(context, game),
                ),

                const SizedBox(height: 32),
                // Spacer to push content up if needed
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBotDifficultyDialog(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Bot Difficulty'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDifficultyOption(ctx, game, 1, 'Beginner', 'Perfect for learning', Colors.green),
            _buildDifficultyOption(ctx, game, 2, 'Easy', 'Casual play', Colors.lightGreen),
            _buildDifficultyOption(ctx, game, 3, 'Medium', 'A fair challenge', Colors.orange),
            _buildDifficultyOption(ctx, game, 4, 'Hard', 'For experienced players', Colors.deepOrange),
            _buildDifficultyOption(ctx, game, 5, 'Expert', 'Maximum difficulty', Colors.red),
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Text(
          '$level',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () {
        Navigator.pop(context);
        game.createGame('10+0', isBot: true, botDifficulty: level);
      },
    );
  }

  void _showPlayOptionsDialog(BuildContext context, GameProvider game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Play with Friends'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle, color: Colors.blue),
              title: const Text('Create New Game'),
              subtitle: const Text('Get a code to share'),
              onTap: () {
                Navigator.pop(ctx);
                game.createGame('10+0', isBot: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.input, color: Colors.green),
              title: const Text('Join Game'),
              subtitle: const Text('Enter a code'),
              onTap: () {
                Navigator.pop(ctx);
                _showJoinGameDialog(context, game);
              },
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
        title: const Text('Join Game'),
        content: TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Game Code',
            hintText: 'Enter 6-digit code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
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

  Widget _buildActionButton(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return CustomButton(
      label: title,
      icon: icon,
      color: color,
      onPressed: onTap,
    );
  }
}
