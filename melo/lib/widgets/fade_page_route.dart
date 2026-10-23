import 'package:flutter/material.dart';

class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadePageRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeIn = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            );
            final fadeOut = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(fadeIn),
              child: FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.0).animate(fadeOut),
                child: child,
              ),
            );
          },
        );
}
