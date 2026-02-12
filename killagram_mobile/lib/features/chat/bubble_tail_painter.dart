import 'package:flutter/material.dart';

class BubbleTailPainter extends CustomPainter {
  BubbleTailPainter({required this.color, required this.isOutgoing});

  final Color color;
  final bool isOutgoing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isOutgoing) {
      path.moveTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.quadraticBezierTo(
        size.width * 0.2,
        size.height * 0.2,
        size.width,
        0,
      );
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.2,
        0,
        0,
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isOutgoing != isOutgoing;
  }
}
