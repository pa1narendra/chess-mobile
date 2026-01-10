import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController(); 
  
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await Provider.of<AuthProvider>(context, listen: false).login(
          _usernameController.text, // Use Username for login
          _passwordController.text,
        );
      } else {
        await Provider.of<AuthProvider>(context, listen: false).register(
          _usernameController.text,
          _emailController.text,
          _passwordController.text,
        );
      }
    } catch (e) {
      final errorMessage = e.toString();
      // Check if it's a connection error and prompt to configure server IP
      if (errorMessage.contains('Connection error') ||
          errorMessage.contains('timed out') ||
          errorMessage.contains('SocketException')) {
        _showConnectionErrorDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showConfigDialog() async {
      final ipController = TextEditingController(text: Config.serverIp);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("Configure Server Connection"),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    const Text("Enter your computer's local IP address:"),
                    const SizedBox(height: 10),
                    TextField(
                        controller: ipController,
                        decoration: const InputDecoration(
                            labelText: "Server IP (e.g. 192.168.1.100)",
                            border: OutlineInputBorder(),
                        ),
                    ),
                ],
            ),
            actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel"),
                ),
                ElevatedButton(
                    onPressed: () async {
                        if (ipController.text.isNotEmpty) {
                            await Config.setServerIp(ipController.text);
                            if (mounted) Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Server IP Updated! Restart App Recommended.")),
                            );
                        }
                    },
                    child: const Text("Save"),
                ),
            ],
        ),
      );
  }

  Future<void> _showConnectionErrorDialog() async {
    final ipController = TextEditingController(text: Config.serverIp);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Cannot Connect to Server"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Could not reach the server. If you're using a physical device, "
              "you need to enter your computer's local IP address.",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              "To find your IP:\n"
              "• Windows: Run 'ipconfig' in CMD\n"
              "• Mac/Linux: Run 'ifconfig' in Terminal\n"
              "Look for an address like 192.168.x.x",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "Server IP Address",
                hintText: "e.g., 192.168.1.100",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ipController.text.isNotEmpty) {
                await Config.setServerIp(ipController.text);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Server IP updated! Try again."),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text("Save & Retry"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Authentication"),
        actions: [
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _showConfigDialog,
                tooltip: "Configure Server IP",
            )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.people_alt, size: 64, color: Color(0xFF4F46E5)),
              const SizedBox(height: 24),
              Text(
                _isLogin ? 'Welcome Back' : 'Create Account',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Username is required for BOTH Login and Signup now
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              
              // Email is ONLY required for Signup
              if (!_isLogin) ...[
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
              ],
              
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : Text(_isLogin ? 'Sign In' : 'Sign Up', style: const TextStyle(fontSize: 16, color: Colors.white)),
              ),
              
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? 'Don\'t have an account? Sign Up' : 'Already have an account? Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
