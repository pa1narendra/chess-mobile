import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../api/api_service.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _error;

  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _countryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.user?['_id'] ?? auth.user?['id'];
    if (userId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.getUserProfile(userId);
      setState(() {
        _profile = result['data'];
        _displayNameController.text = _profile?['profile']?['displayName'] ?? '';
        _bioController.text = _profile?['profile']?['bio'] ?? '';
        _countryController.text = _profile?['profile']?['country'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() => _isSaving = true);

    try {
      await ApiService.updateProfile(token, {
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'country': _countryController.text.trim(),
      });

      // Refresh user data in auth provider
      await Provider.of<AuthProvider>(context, listen: false).refreshUser();

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated'),
            backgroundColor: AppColors.emeraldGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppColors.roseError),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Profile', style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (!_isLoading && _profile != null)
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit, color: AppColors.textSecondary),
              onPressed: () => setState(() => _isEditing = !_isEditing),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.roseError, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _loadProfile, child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildProfileHeader(),
                      const SizedBox(height: 20),
                      _buildRatingCard(),
                      const SizedBox(height: 16),
                      _buildStatsCard(),
                      const SizedBox(height: 16),
                      if (_isEditing) _buildEditForm(),
                      if (_profile?['ratingHistory'] != null && (_profile!['ratingHistory'] as List).isNotEmpty)
                        _buildRatingHistory(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileHeader() {
    final username = _profile?['username'] ?? 'Player';
    final displayName = _profile?['profile']?['displayName'];
    final bio = _profile?['profile']?['bio'];
    final rank = _profile?['rank'] ?? '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.tealAccent.withValues(alpha: 0.15),
            child: Text(
              username[0].toUpperCase(),
              style: const TextStyle(color: AppColors.tealAccent, fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName?.isNotEmpty == true ? displayName! : username,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (displayName?.isNotEmpty == true)
            Text('@$username', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Rank #$rank', style: const TextStyle(color: AppColors.tealAccent, fontSize: 14, fontWeight: FontWeight.w500)),
          if (bio?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(bio!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingCard() {
    final rating = _profile?['rating'] ?? 1200;
    final peakRating = _profile?['peakRating'] ?? 1200;
    final rd = _profile?['ratingDeviation'] ?? 350;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRatingStat('Rating', '$rating', AppColors.tealAccent),
          Container(width: 1, height: 40, color: AppColors.borderColor),
          _buildRatingStat('Peak', '$peakRating', AppColors.amberWarning),
          Container(width: 1, height: 40, color: AppColors.borderColor),
          _buildRatingStat('RD', '$rd', AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildRatingStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildStatsCard() {
    final stats = _profile?['stats'] ?? {};
    final games = stats['games'] ?? 0;
    final wins = stats['wins'] ?? 0;
    final losses = stats['losses'] ?? 0;
    final draws = stats['draws'] ?? 0;
    final streak = stats['currentStreak'] ?? 0;
    final bestStreak = stats['bestStreak'] ?? 0;
    final winRate = games > 0 ? (wins / games * 100).round() : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Statistics', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatItem('Games', '$games', AppColors.electricBlue)),
              Expanded(child: _buildStatItem('Wins', '$wins', AppColors.emeraldGreen)),
              Expanded(child: _buildStatItem('Losses', '$losses', AppColors.roseError)),
              Expanded(child: _buildStatItem('Draws', '$draws', AppColors.amberWarning)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatItem('Win Rate', '$winRate%', AppColors.tealAccent)),
              Expanded(
                child: _buildStatItem(
                  'Streak',
                  streak > 0 ? '+$streak' : '$streak',
                  streak > 0 ? AppColors.emeraldGreen : streak < 0 ? AppColors.roseError : AppColors.textMuted,
                ),
              ),
              Expanded(child: _buildStatItem('Best', '+$bestStreak', AppColors.amberWarning)),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildEditForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tealAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edit Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildField('Display Name', _displayNameController, 'How others see you'),
          const SizedBox(height: 12),
          _buildField('Bio', _bioController, 'Tell us about yourself', maxLines: 3),
          const SizedBox(height: 12),
          _buildField('Country Code', _countryController, 'e.g. US, IN, GB'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tealAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.tealAccent),
        ),
        filled: true,
        fillColor: AppColors.deepDark,
      ),
    );
  }

  Widget _buildRatingHistory() {
    final history = (_profile?['ratingHistory'] as List?) ?? [];
    if (history.length < 2) return const SizedBox.shrink();

    final ratings = history.map((e) => (e['r'] as num).toDouble()).toList();
    final minRating = ratings.reduce((a, b) => a < b ? a : b) - 20;
    final maxRating = ratings.reduce((a, b) => a > b ? a : b) + 20;
    final range = maxRating - minRating;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rating History', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _RatingChartPainter(ratings, minRating, range),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingChartPainter extends CustomPainter {
  final List<double> ratings;
  final double minRating;
  final double range;

  _RatingChartPainter(this.ratings, this.minRating, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    if (ratings.length < 2) return;

    final paint = Paint()
      ..color = AppColors.tealAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.tealAccent.withValues(alpha: 0.3), AppColors.tealAccent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < ratings.length; i++) {
      final x = (i / (ratings.length - 1)) * size.width;
      final y = size.height - ((ratings[i] - minRating) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots at start and end
    final dotPaint = Paint()..color = AppColors.tealAccent..style = PaintingStyle.fill;
    final lastX = size.width;
    final lastY = size.height - ((ratings.last - minRating) / range) * size.height;
    canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
