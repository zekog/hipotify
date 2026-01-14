import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileScaffold;
  final Widget tvScaffold;

  const ResponsiveLayout({
    super.key,
    required this.mobileScaffold,
    required this.tvScaffold,
  });

  static bool isTv(BuildContext context) {
    // Simple width check for now, can be enhanced with Platform check
    return MediaQuery.of(context).size.width > 600;
  }

  @override
  Widget build(BuildContext context) {
    if (isTv(context)) {
      return tvScaffold;
    } else {
      return mobileScaffold;
    }
  }
}
