import 'package:flutter/material.dart';

class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothPageRoute({required this.page, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.85, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0.0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
      );
}
