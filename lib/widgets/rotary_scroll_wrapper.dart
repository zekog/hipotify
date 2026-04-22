import 'package:flutter/material.dart';
import 'package:wear_os_scrollbar/wear_os_scrollbar.dart';

/// Wraps a scrollable widget with WearOsScrollbar to support native
/// Wear OS rotary crown scrolling and display an elegant indicator.
class RotaryScrollWrapper extends StatelessWidget {
  final Widget child;
  final ScrollController controller;

  const RotaryScrollWrapper({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return WearOsScrollbar(
      controller: controller,
      hapticFeedback: WearOsHapticFeedback.lightImpact,
      indicatorColor: Colors.white,
      backgroundColor: Colors.white24,
      strokeWidth: 4.0,
      totalAngle: 40.0,
      child: child,
    );
  }
}
