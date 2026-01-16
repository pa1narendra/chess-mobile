import 'package:flutter/material.dart';
import '../main.dart';

class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color? color;
  final Color? gradientEnd;
  final IconData? icon;
  final bool outlined;
  final double? width;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.gradientEnd,
    this.icon,
    this.outlined = false,
    this.width,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? AppColors.tealAccent;
    final hasGradient = widget.gradientEnd != null;

    if (widget.outlined) {
      return _buildOutlinedButton(baseColor);
    }

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          gradient: hasGradient
              ? LinearGradient(
                  colors: [baseColor, widget.gradientEnd!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: hasGradient ? null : baseColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: baseColor.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTapDown: widget.isLoading ? null : (_) => setState(() => _isPressed = true),
            onTapUp: widget.isLoading ? null : (_) => setState(() => _isPressed = false),
            onTapCancel: widget.isLoading ? null : () => setState(() => _isPressed = false),
            onTap: widget.isLoading ? null : widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton(Color color) {
    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTapDown: widget.isLoading ? null : (_) => setState(() => _isPressed = true),
            onTapUp: widget.isLoading ? null : (_) => setState(() => _isPressed = false),
            onTapCancel: widget.isLoading ? null : () => setState(() => _isPressed = false),
            onTap: widget.isLoading ? null : widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: _buildContent(textColor: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({Color textColor = Colors.white}) {
    if (widget.isLoading) {
      return Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            color: textColor,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: textColor, size: 22),
          const SizedBox(width: 10),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 16,
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Game Mode Card - used on home screen
class GameModeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool isLoading;

  const GameModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<GameModeCard> createState() => _GameModeCardState();
}

class _GameModeCardState extends State<GameModeCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: widget.gradient[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTapDown: widget.isLoading ? null : (_) => setState(() => _isPressed = true),
            onTapUp: widget.isLoading ? null : (_) => setState(() => _isPressed = false),
            onTapCancel: widget.isLoading ? null : () => setState(() => _isPressed = false),
            onTap: widget.isLoading ? null : widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(widget.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.8),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
