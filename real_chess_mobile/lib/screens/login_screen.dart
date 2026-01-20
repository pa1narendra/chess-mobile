import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/config.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  // Focus nodes to track which field is focused
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _shouldHideLogo = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    // Listen to focus changes - hide logo when any field is focused
    _usernameFocus.addListener(_updateLogoVisibility);
    _emailFocus.addListener(_updateLogoVisibility);
    _passwordFocus.addListener(_updateLogoVisibility);
  }

  void _updateLogoVisibility() {
    final shouldHide = _usernameFocus.hasFocus || _emailFocus.hasFocus || _passwordFocus.hasFocus;
    if (shouldHide != _shouldHideLogo) {
      setState(() => _shouldHideLogo = shouldHide);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_usernameController.text.trim().isEmpty) {
      _showError('Please enter your username');
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      _showError('Please enter your password');
      return;
    }
    if (!_isLogin && _emailController.text.trim().isEmpty) {
      _showError('Please enter your email');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await Provider.of<AuthProvider>(context, listen: false).login(
          _usernameController.text,
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
      if (errorMessage.contains('Connection error') ||
          errorMessage.contains('timed out') ||
          errorMessage.contains('SocketException')) {
        _showConnectionErrorDialog();
      } else {
        _showError(errorMessage.replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.roseError,
      ),
    );
  }

  void _toggleAuthMode() {
    _animationController.reset();
    setState(() => _isLogin = !_isLogin);
    _animationController.forward();
  }

  Future<void> _showConfigDialog() async {
    final ipController = TextEditingController(text: Config.serverIp);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings, color: AppColors.tealAccent),
            const SizedBox(width: 8),
            const Text("Server Settings"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Enter your computer's local IP address:",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "Server IP",
                hintText: "e.g., 192.168.1.100",
                prefixIcon: Icon(Icons.dns),
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
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text("Server IP Updated!"),
                      ],
                    ),
                    backgroundColor: AppColors.emeraldGreen,
                  ),
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
        title: Row(
          children: [
            Icon(Icons.wifi_off, color: AppColors.roseError),
            const SizedBox(width: 8),
            const Text("Connection Failed"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.roseError.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.roseError.withOpacity(0.3)),
              ),
              child: Text(
                "Could not connect to the server. If using a physical device, enter your computer's local IP address.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "How to find your IP:",
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              "Windows: Run 'ipconfig' in CMD\nMac/Linux: Run 'ifconfig' in Terminal\nLook for: 192.168.x.x",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "Server IP Address",
                hintText: "e.g., 192.168.1.100",
                prefixIcon: Icon(Icons.dns),
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
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text("Server IP updated! Try again."),
                        ],
                      ),
                      backgroundColor: AppColors.emeraldGreen,
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showConfigDialog,
            tooltip: "Server Settings",
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              // Add top spacing only when logo is visible
              if (!_shouldHideLogo) const SizedBox(height: 40),

              // Logo/Branding Section - hide only when email/password focused
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _shouldHideLogo
                    ? const SizedBox(height: 20)
                    : _buildBrandSection(),
              ),

              SizedBox(height: _shouldHideLogo ? 20 : 40),

              // Form Card
              FadeTransition(
                opacity: _fadeAnimation,
                child: _buildFormCard(),
              ),

              const SizedBox(height: 24),

              // Toggle auth mode
              _buildAuthToggle(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.tealAccent.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.tealAccent.withOpacity(0.3), width: 2),
          ),
          child: const Icon(
            Icons.grid_view_rounded,
            size: 48,
            color: AppColors.tealAccent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Chessing',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Play chess online with friends',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Form Title
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _isLogin ? 'Welcome Back' : 'Create Account',
              key: ValueKey(_isLogin),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLogin ? 'Sign in to continue playing' : 'Join and start playing',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Username Field
          _buildTextField(
            controller: _usernameController,
            focusNode: _usernameFocus,
            label: 'Username',
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
          ),

          // Email Field (only for signup)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !_isLogin
                ? Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 16),

          // Password Field
          _buildTextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.textMuted,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),

          const SizedBox(height: 24),

          // Submit Button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tealAccent,
                disabledBackgroundColor: AppColors.tealAccent.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isLogin ? Icons.login : Icons.person_add, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isLogin ? 'Sign In' : 'Create Account',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmitted,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildAuthToggle() {
    return TextButton(
      onPressed: _toggleAuthMode,
      child: Text.rich(
        TextSpan(
          text: _isLogin ? "Don't have an account? " : "Already have an account? ",
          style: TextStyle(color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: _isLogin ? 'Sign Up' : 'Sign In',
              style: TextStyle(
                color: AppColors.tealAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
