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
  @override
  void initState() {
    super.initState();
    // Connect socket when Home loads
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      Provider.of<GameProvider>(context, listen: false).initSocket(auth.token!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        // Automatically navigate to GameScreen if in game
        if (game.isInGame) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             Navigator.of(context).push(
               MaterialPageRoute(builder: (_) => const GameScreen()),
             );
          });
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
                  () => game.createGame('10+0', isBot: true),
                ),
                 const SizedBox(height: 16),
                _buildActionButton(
                  context,
                  'Create Game',
                  Icons.add_circle,
                  Colors.blue,
                  () => game.createGame('10+0'),
                ),

                const SizedBox(height: 32),
                const Text('Pending Games', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Expanded(
                  child: game.pendingGames.isEmpty
                      ? const Center(child: Text('No pending games. Create one!'))
                      : ListView.builder(
                          itemCount: game.pendingGames.length,
                          itemBuilder: (context, index) {
                            final g = game.pendingGames[index];
                            return Card(
                              child: ListTile(
                                title: Text(g['hostName'] ?? 'Unknown'),
                                subtitle: Text('${g['timeControl']} • ${g['isBot'] ? 'Bot' : 'Human'}'),
                                trailing: ElevatedButton(
                                  onPressed: () => game.joinGame(g['id']),
                                  child: const Text('Join'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
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
