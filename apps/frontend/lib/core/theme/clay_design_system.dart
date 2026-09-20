import 'package:flutter/material.dart';

/// Comprehensive Clay-Inspired Design System for Easy Chat
/// 
/// Embodying Apple-level simplicity, Google-quality product polish,
/// and Linear-level precision with tactile clay surfaces.
class ClayColors {
  // Brand Canvas & Neutral Surfaces
  static const Color canvas = Color(0xFFF0EEE9);
  static const Color background = canvas;
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSurface = card;
  static const Color cardElevated = Color(0xFFFDFCFA);
  static const Color surfaceMuted = Color(0xFFE8E5DF);
  static const Color surfaceSubtle = Color(0xFFF5F3EE);

  // Primary Brand Accent
  static const Color accent = Color(0xFFF15596);
  static const Color accentHover = Color(0xFFE24386);
  static const Color accentLight = Color(0xFFFDEBF3);
  static const Color accentGlow = Color(0x40F15596);

  // Typography Hierarchy
  static const Color textPrimary = Color(0xFF1E1D1B);
  static const Color textSecondary = Color(0xFF7A7873);
  static const Color textTertiary = Color(0xFFA3A09A);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Semantic Status Tones
  static const Color success = Color(0xFF22A06B);
  static const Color successSoft = Color(0xFFEAF8F1);
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerSoft = Color(0xFFFDF0F1);
  static const Color warning = Color(0xFFE09520);
  static const Color warningSoft = Color(0xFFFEF7EC);

  // Micro-borders & Highlights
  static const Color borderSoft = Color(0x12000000);
  static const Color borderSubtle = borderSoft;
  static const Color borderHighlight = Color(0x66FFFFFF);
}

class ClayShadows {
  /// Soft ambient clay card elevation
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D443D36),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Elevated card for prominent interaction (Incoming Request banner, modals)
  static const List<BoxShadow> cardElevated = [
    BoxShadow(
      color: Color(0x14443D36),
      blurRadius: 26,
      offset: Offset(0, 10),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];

  /// Vibrant tactile primary button shadow
  static const List<BoxShadow> buttonAccent = [
    BoxShadow(
      color: ClayColors.accentGlow,
      blurRadius: 16,
      offset: Offset(0, 6),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x15000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  /// Neutral secondary button shadow
  static const List<BoxShadow> buttonNeutral = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x40FFFFFF),
      blurRadius: 2,
      offset: Offset(0, -1),
    ),
  ];

  static const List<BoxShadow> button = buttonNeutral;
}

/// Soft clay-style elevated card container
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
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 24.0,
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
      resolvedRadius = BorderRadius.circular(24.0);
    }

    Widget cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? ClayColors.card,
        borderRadius: resolvedRadius,
        boxShadow: shadows ?? ClayShadows.card,
        border: border ?? Border.all(color: ClayColors.borderSoft, width: 1),
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

/// Tactile primary button with smooth micro-interaction
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
    this.borderRadius = 18.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
    final bg = widget.backgroundColor ?? ClayColors.accent;
    final fg = widget.foregroundColor ?? ClayColors.textOnAccent;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: isEnabled ? bg : bg.withOpacity(0.4),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: isEnabled ? ClayShadows.buttonAccent : null,
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: fg,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 18, color: fg),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
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

/// Tactile neutral secondary button (for Deny, Cancel, View)
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
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });

  @override
  State<ClaySecondaryButton> createState() => _ClaySecondaryButtonState();
}

class _ClaySecondaryButtonState extends State<ClaySecondaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.textColor ?? ClayColors.textPrimary;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Container(
        decoration: BoxDecoration(
          color: ClayColors.surfaceMuted,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: ClayShadows.buttonNeutral,
          border: Border.all(color: ClayColors.borderSoft),
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
                    Icon(widget.icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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

/// Tactile pill badge for clean distance & status presentation
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
    final bg = backgroundColor ?? (isHighlighted ? ClayColors.accentLight : ClayColors.surfaceSubtle);
    final fg = textColor ?? (isHighlighted ? ClayColors.accent : ClayColors.textPrimary);
    final ic = iconColor ?? fg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClayColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ic),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Official Easy Chat Brand Mark
/// 
/// Renders the official compass arrow mark with orbital ring
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
              ringColor: ringColor ?? const Color(0xFF2C64E8),
              arrowColor: arrowColor ?? ClayColors.textPrimary,
            ),
          );
        },
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
