import 'package:flutter/material.dart';

/// Centralized Design System Color Tokens for Easy Chat
///
/// Restrained, modern Google/Material-inspired visual system
/// with Primary Blue (#3B6FE0) and Soft Warm Off-White/Beige (#F8F7F3).
class AppColors {
  // ---------------------------------------------------------------------------
  // Primary Brand Identity (Blue)
  // ---------------------------------------------------------------------------
  /// Core brand blue for primary buttons, active controls, sent chat bubbles,
  /// ON toggle tracks, selected navigation items, and send buttons.
  static const Color primary = Color(0xFF3B6FE0);

  /// Slightly darker blue for pressed/hover micro-interaction states.
  static const Color primaryPressed = Color(0xFF2E5DC0);

  /// Subtle soft tint used strictly for selected background chips or hover highlights.
  static const Color primaryLight = Color(0xFFEBF1FD);

  /// High-contrast text on primary blue surfaces.
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Neutral Canvas & Surface Scale
  // ---------------------------------------------------------------------------
  /// Soft warm off-white/beige background canvas for all screens.
  static const Color background = Color(0xFFF8F7F3);

  /// Crisp white for cards, sheets, dialogs, and received chat bubbles.
  static const Color surface = Color(0xFFFFFFFF);

  /// Neutral container/pill surface for chips, avatars, and secondary containers.
  static const Color surfaceVariant = Color(0xFFF0EEE9);

  /// Subtle neutral for input fields and inactive secondary containers.
  static const Color surfaceSubtle = Color(0xFFF5F3EF);

  // ---------------------------------------------------------------------------
  // Typography Hierarchy (Regular 400 & Medium 500)
  // ---------------------------------------------------------------------------
  /// High-contrast dark neutral for headings, titles, and body copy.
  static const Color textPrimary = Color(0xFF1F2328);

  /// Neutral gray for secondary copy, handles, and timestamps.
  static const Color textSecondary = Color(0xFF6E737A);

  /// Muted neutral gray for placeholders, disabled labels, and subtle hints.
  static const Color textMuted = Color(0xFF9EA3AA);

  // ---------------------------------------------------------------------------
  // Borders, Dividers & Outlines
  // ---------------------------------------------------------------------------
  /// Very subtle neutral gray border (approximately 0.5–1px).
  static const Color border = Color(0xFFE5E2DC);

  /// Ultra-subtle border for nested elements.
  static const Color borderSubtle = Color(0xFFECEAE4);

  /// Crisp divider line separating sections and list rows.
  static const Color divider = Color(0xFFEAE7E1);

  // ---------------------------------------------------------------------------
  // Interactive Controls & Icons
  // ---------------------------------------------------------------------------
  /// Neutral gray icon color across all navigation, cards, and list rows.
  static const Color icon = Color(0xFF6E737A);

  /// Inactive, disabled controls and tracks (NEVER tinted blue).
  static const Color disabled = Color(0xFFD4D1CA);

  // ---------------------------------------------------------------------------
  // Toggle System (38 × 22 px)
  // ---------------------------------------------------------------------------
  /// Neutral gray OFF toggle track (strictly neutral gray, never tinted blue).
  static const Color toggleTrackOff = Color(0xFFD4D1CA);

  /// Blue ON toggle track (#3B6FE0).
  static const Color toggleTrackOn = Color(0xFF3B6FE0);

  /// Pure white toggle thumb.
  static const Color toggleThumb = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Semantic Status Colors
  // ---------------------------------------------------------------------------
  /// Success green ONLY for online status dot and active nearby status.
  static const Color success = Color(0xFF10B981);

  /// Soft green background for status badges.
  static const Color successSoft = Color(0xFFE8F7F0);

  /// Destructive/danger red for errors and account deletion.
  static const Color danger = Color(0xFFDC2626);

  /// Soft danger background for error banners and warnings.
  static const Color dangerSoft = Color(0xFFFEE2E2);

  /// Warning amber for cautionary states.
  static const Color warning = Color(0xFFD97706);

  /// Soft warning background for updating/stale indicators.
  static const Color warningSoft = Color(0xFFFEF3C7);

  // ---------------------------------------------------------------------------
  // Rare Accent Highlight (Pink / Magenta)
  // ---------------------------------------------------------------------------
  /// Rare pink accent reserved strictly for special tags like "New here".
  /// Max 1 highlight badge per relevant card/screen; NEVER used for buttons,
  /// toggles, primary controls, or chat bubbles.
  static const Color pinkHighlight = Color(0xFFF43F5E);

  /// Soft background for the rare "New here" chip.
  static const Color pinkHighlightBackground = Color(0xFFFFF1F2);
}
