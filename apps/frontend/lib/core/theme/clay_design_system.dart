import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Comprehensive Design System for Easy Chat
/// 
/// Restrained, modern Google/Material-inspired visual system
/// centered around Primary Blue (#3B6FE0) and Soft Warm Off-White/Beige (#F8F7F3).
class ClayColors {
  // Brand Canvas & Neutral Surfaces
  static const Color canvas = AppColors.background;
  static const Color background = AppColors.background;
  static const Color card = AppColors.surface;
  static const Color cardSurface = AppColors.surface;
  static const Color cardElevated = AppColors.surface;
  static const Color surfaceMuted = AppColors.surfaceVariant;
  static const Color surfaceSubtle = AppColors.surfaceSubtle;

  // Primary Brand Accent (Blue #3B6FE0)
  static const Color accent = AppColors.primary;
  static const Color accentHover = AppColors.primaryPressed;
  static const Color accentLight = AppColors.primaryLight;
  static const Color accentGlow = Color(0x263B6FE0);

  // Typography Hierarchy (Regular 400 & Medium 500)
  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textTertiary = AppColors.textMuted;
  static const Color textOnAccent = AppColors.textOnPrimary;

  // Semantic Status Tones
  static const Color success = AppColors.success;
  static const Color successSoft = AppColors.successSoft;
  static const Color danger = AppColors.danger;
  static const Color dangerSoft = AppColors.dangerSoft;
  static const Color warning = AppColors.warning;
  static const Color warningSoft = AppColors.warningSoft;

  // Micro-borders & Outlines (subtle 0.5–1px)
  static const Color borderSoft = AppColors.border;
  static const Color borderSubtle = AppColors.borderSubtle;
  static const Color borderHighlight = Colors.transparent;

  // Rare Accent Highlight (Pink / Magenta for "New here" chip only)
  static const Color pinkHighlight = AppColors.pinkHighlight;
  static const Color pinkHighlightBackground = AppColors.pinkHighlightBackground;
}

class ClayShadows {
  /// Subtle ambient card shadow (no heavy shadows or excessive elevation)
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Elevated card for prominent modals/dialogs
  static const List<BoxShadow> cardElevated = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Primary button has NO shadow
  static const List<BoxShadow> buttonAccent = [];

  /// Secondary button has NO shadow
  static const List<BoxShadow> buttonNeutral = [];

  static const List<BoxShadow> button = [];
}

/// Clean card container with 12px radius and subtle neutral border
class ClayCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final dynamic borderRadius;
  final Color? color;
  final List<BoxShadow>? shadows;
  final Border? border;
  final VoidCallback? onTap;

  const ClayCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 12.0,
    this.color,
    this.shadows,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    BorderRadiusGeometry resolvedRadius;
    if (borderRadius is BorderRadiusGeometry) {
      resolvedRadius = borderRadius as BorderRadiusGeometry;
    } else if (borderRadius is num) {
      resolvedRadius = BorderRadius.circular((borderRadius as num).toDouble());
    } else {
      resolvedRadius = BorderRadius.circular(12.0);
    }

    Widget cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: resolvedRadius,
        boxShadow: shadows ?? ClayShadows.card,
        border: border ?? Border.all(color: AppColors.border, width: 0.8),
      ),
      child: child,
    );

    if (margin != null) {
      cardContent = Padding(padding: margin!, child: cardContent);
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cardContent,
      );
    }

    return cardContent;
  }
}

/// Primary button: Solid #3B6FE0, white text, 8px radius, no shadow, no gradient
class ClayButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;

  const ClayButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.width,
  });

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null && !widget.isLoading;
    final bg = widget.backgroundColor ?? AppColors.primary;
    final fg = widget.foregroundColor ?? AppColors.textOnPrimary;
    final activeBg = _isPressed ? AppColors.primaryPressed : bg;

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: isEnabled ? activeBg : AppColors.disabled,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onHighlightChanged: (val) {
              if (isEnabled) setState(() => _isPressed = val);
            },
            onTap: widget.onPressed,
            child: Padding(
              padding: widget.padding,
              child: widget.isLoading
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: fg,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 16, color: fg),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
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

/// Secondary button: Transparent background, neutral outline, 8px radius, medium-weight text
class ClaySecondaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? textColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const ClaySecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.textColor,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  State<ClaySecondaryButton> createState() => _ClaySecondaryButtonState();
}

class _ClaySecondaryButtonState extends State<ClaySecondaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.textColor ?? AppColors.textPrimary;

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: Container(
        decoration: BoxDecoration(
          color: _isPressed ? AppColors.surfaceVariant : AppColors.surface,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onHighlightChanged: (val) => setState(() => _isPressed = val),
            onTap: widget.onPressed,
            child: Padding(
              padding: widget.padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 15, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
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

/// One consistent chip style across the application
/// Transparent/white background, thin neutral-gray border, small rounded rectangle, gray text
/// Rare pink highlight only for "New here" badge
class ClayBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;
  final bool isHighlighted;

  const ClayBadge({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ??
        (isHighlighted ? AppColors.pinkHighlightBackground : AppColors.surface);
    final fg = textColor ??
        (isHighlighted ? AppColors.pinkHighlight : AppColors.textSecondary);
    final border = isHighlighted
        ? Border.all(color: AppColors.pinkHighlight.withOpacity(0.3), width: 0.8)
        : Border.all(color: AppColors.border, width: 0.8);
    final ic = iconColor ?? fg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ic),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone Toggle System (38 × 22 px)
/// OFF: neutral gray track (#D4D1CA), white thumb
/// ON: #3B6FE0 track, white thumb, thumb moves to right
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const width = 38.0;
    const height = 22.0;
    const thumbSize = 16.0;
    const padding = 3.0;

    final isEnabled = onChanged != null;
    final trackColor = value
        ? (isEnabled ? AppColors.toggleTrackOn : AppColors.disabled)
        : (isEnabled ? AppColors.toggleTrackOff : AppColors.disabled.withOpacity(0.6));

    return GestureDetector(
      onTap: isEnabled ? () => onChanged!(!value) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: trackColor,
        ),
        padding: const EdgeInsets.all(padding),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: thumbSize,
          height: thumbSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.toggleThumb,
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Official Easy Chat Brand Mark
/// 
/// Renders the official compass arrow mark with orbital ring.
/// The original logo asset is strictly preserved without modification.
class EasyChatLogoMark extends StatelessWidget {
  final double size;
  final Color? ringColor;
  final Color? arrowColor;

  const EasyChatLogoMark({
    super.key,
    this.size = 54.0,
    this.ringColor,
    this.arrowColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/images/easy_chat_logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Elegant vector canvas fallback
            return CustomPaint(
              size: Size(size, size),
              painter: _EasyChatVectorPainter(
                ringColor: ringColor ?? AppColors.primary,
                arrowColor: arrowColor ?? AppColors.surface,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EasyChatVectorPainter extends CustomPainter {
  final Color ringColor;
  final Color arrowColor;

  _EasyChatVectorPainter({required this.ringColor, required this.arrowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // 1. Draw orbital elliptical ring tilted diagonally
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.45); // ~26 degree tilt

    final ovalRect = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.92,
      height: h * 0.44,
    );
    canvas.drawOval(ovalRect, ringPaint);
    canvas.restore();

    // 2. Draw compass arrow pointer
    final arrowPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;

    final path = Path();
    // Tip pointing top-right
    path.moveTo(w * 0.78, h * 0.28);
    // Left wing
    path.lineTo(w * 0.18, h * 0.68);
    // Inset center notch
    path.lineTo(w * 0.45, h * 0.60);
    // Bottom wing
    path.lineTo(w * 0.40, h * 0.86);
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
