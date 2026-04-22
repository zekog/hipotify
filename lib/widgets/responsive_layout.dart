import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Device types for responsive layouts
enum DeviceType {
  mobile,
  tablet,
  tv,
  wearOs,
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileScaffold;
  final Widget? tabletScaffold;
  final Widget? tvScaffold;
  final Widget? wearOsScaffold;

  const ResponsiveLayout({
    super.key,
    required this.mobileScaffold,
    this.tabletScaffold,
    this.tvScaffold,
    this.wearOsScaffold,
  });

  static DeviceType? _cachedType;

  /// Get current device type
  static DeviceType getDeviceType(BuildContext context) {
    if (_cachedType != null) return _cachedType!;

    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;
    final diagonal = _calculateDiagonal(width, height);

    // Check for Wear OS:
    final isSquareOrRound = (width / height) > 0.8 && (width / height) < 1.2;
    final isSmallScreen = diagonal < 400; // Less than 400 logical pixels

    if (isSmallScreen && isSquareOrRound) {
      _cachedType = DeviceType.wearOs;
      return DeviceType.wearOs;
    }

    // Check for TV: Large width
    if (width > 900) {
      return DeviceType.tv;
    }

    // Check for Tablet
    if (width > 600) {
      return DeviceType.tablet;
    }

    return DeviceType.mobile;
  }

  /// Check if device is Wear OS
  static bool isWearOs(BuildContext context) {
    return getDeviceType(context) == DeviceType.wearOs;
  }

  /// Check if device is TV
  static bool isTv(BuildContext context) {
    final deviceType = getDeviceType(context);
    return deviceType == DeviceType.tv;
  }

  /// Check if device is tablet
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// Check if device is mobile
  static bool isMobile(BuildContext context) {
    return getDeviceType(context) == DeviceType.mobile;
  }

  /// Calculate screen diagonal in logical pixels
  static double _calculateDiagonal(double width, double height) {
    return math.sqrt(width * width + height * height);
  }

  /// Get responsive value based on device type
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? tv,
    T? wearOs,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.wearOs:
        return wearOs ?? mobile;
      case DeviceType.tv:
        return tv ?? tablet ?? mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.mobile:
      default:
        return mobile;
    }
  }

  /// Get screen size category for responsive design
  static ScreenSizeCategory getScreenSizeCategory(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 300) return ScreenSizeCategory.tiny; // Small watch
    if (width < 400) return ScreenSizeCategory.small; // Large watch
    if (width < 600) return ScreenSizeCategory.medium; // Phone
    if (width < 900) return ScreenSizeCategory.large; // Tablet
    return ScreenSizeCategory.extraLarge; // TV
  }

  @override
  Widget build(BuildContext context) {
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.wearOs:
        if (wearOsScaffold != null) return wearOsScaffold!;
        return mobileScaffold;
      case DeviceType.tv:
        if (tvScaffold != null) return tvScaffold!;
        return tabletScaffold ?? mobileScaffold;
      case DeviceType.tablet:
        if (tabletScaffold != null) return tabletScaffold!;
        return mobileScaffold;
      case DeviceType.mobile:
      default:
        return mobileScaffold;
    }
  }
}

/// Screen size categories for fine-tuned responsive design
enum ScreenSizeCategory {
  tiny, // < 300dp (small watches)
  small, // 300-400dp (large watches)
  medium, // 400-600dp (phones)
  large, // 600-900dp (tablets)
  extraLarge, // > 900dp (TVs)
}

/// Wear OS specific constants
class WearOsConstants {
  // Screen sizes
  static const double smallWatchSize = 200; // 38-40mm watches
  static const double mediumWatchSize = 220; // 42-44mm watches
  static const double largeWatchSize = 240; // 46mm+ watches

  // UI spacing
  static const double tinyPadding = 4;
  static const double smallPadding = 8;
  static const double defaultPadding = 12;
  static const double largePadding = 16;

  // Touch targets - minimum 40x40dp for accessibility
  static const double minTouchTarget = 40;
  static const double buttonSize = 48;
  static const double iconSize = 24;
  static const double largeIconSize = 32;

  // Typography
  static const double captionSize = 10;
  static const double bodySize = 12;
  static const double titleSize = 14;
  static const double headlineSize = 16;
  static const double largeHeadlineSize = 20;

  // Animation durations
  static const Duration quickAnimation = Duration(milliseconds: 150);
  static const Duration defaultAnimation = Duration(milliseconds: 300);
}

/// Wear OS specific extensions
extension WearOsContext on BuildContext {
  /// Check if running on Wear OS
  bool get isWearOs => ResponsiveLayout.isWearOs(this);

  /// Get device type
  DeviceType get deviceType => ResponsiveLayout.getDeviceType(this);

  /// Get screen size category
  ScreenSizeCategory get screenSizeCategory =>
      ResponsiveLayout.getScreenSizeCategory(this);

  /// Get safe area for Wear OS (accounts for chin/flat tire)
  EdgeInsets get wearOsSafeArea {
    if (!isWearOs) return EdgeInsets.zero;
    // Typical Wear OS has chin at bottom
    return const EdgeInsets.only(bottom: 24);
  }
}
