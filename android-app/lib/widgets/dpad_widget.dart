import 'package:flutter/material.dart';
import 'package:vgamepad/theme.dart';

class DpadWidget extends StatefulWidget {
  final double size;
  final void Function({required bool up, required bool down, required bool left, required bool right}) onChanged;

  const DpadWidget({super.key, required this.onChanged, this.size = 140});

  @override
  State<DpadWidget> createState() => _DpadWidgetState();
}

class _DpadWidgetState extends State<DpadWidget> {
  bool up = false, down = false, left = false, right = false;

  void _update(Offset local) {
    final s = widget.size;
    final center = Offset(s / 2, s / 2);
    final rel = local - center;
    
    // A proportional deadzone makes scaling the size much safer
    final deadzone = s * 0.12; 

    final newUp = rel.dy < -deadzone;
    final newDown = rel.dy > deadzone;
    final newLeft = rel.dx < -deadzone;
    final newRight = rel.dx > deadzone;

    if (newUp != up || newDown != down || newLeft != left || newRight != right) {
      setState(() {
        up = newUp;
        down = newDown;
        left = newLeft;
        right = newRight;
      });
      widget.onChanged(up: up, down: down, left: left, right: right);
    }
  }

  void _reset() {
    setState(() => up = down = left = right = false);
    widget.onChanged(up: false, down: false, left: false, right: false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          painter: _DpadPainter(up: up, down: down, left: left, right: right),
        ),
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  final bool up, down, left, right;
  _DpadPainter({required this.up, required this.down, required this.left, required this.right});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final armLen = r * 0.96; // half-length of each arm
    final armW = r * 0.60;
    final corner = Radius.circular(armW * 0.30);

    final horiz = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: armLen * 2, height: armW), corner);
    final vert = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: armW, height: armLen * 2), corner);
    final cross = Path.combine(
        PathOperation.union, Path()..addRRect(horiz), Path()..addRRect(vert));

    // Drop shadow.
    canvas.drawPath(
      cross.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Body.
    final bounds = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      cross,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(AppColors.stickFill, Colors.white, 0.18)!,
            AppColors.stickFill,
            Color.lerp(AppColors.stickFill, Colors.black, 0.4)!,
          ],
        ).createShader(bounds),
    );

    // Pressed arms glow (clipped to the cross).
    canvas.save();
    canvas.clipPath(cross);
    final glow = Paint()
      ..color = AppColors.activeAccent.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    if (up) {
      canvas.drawRect(
          Rect.fromLTRB(c.dx - armW / 2, c.dy - armLen, c.dx + armW / 2, c.dy - armW * 0.2), glow);
    }
    if (down) {
      canvas.drawRect(
          Rect.fromLTRB(c.dx - armW / 2, c.dy + armW * 0.2, c.dx + armW / 2, c.dy + armLen), glow);
    }
    if (left) {
      canvas.drawRect(
          Rect.fromLTRB(c.dx - armLen, c.dy - armW / 2, c.dx - armW * 0.2, c.dy + armW / 2), glow);
    }
    if (right) {
      canvas.drawRect(
          Rect.fromLTRB(c.dx + armW * 0.2, c.dy - armW / 2, c.dx + armLen, c.dy + armW / 2), glow);
    }
    canvas.restore();

    // Rim light.
    canvas.drawPath(
      cross,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.28),
    );

    // Centre dimple.
    canvas.drawCircle(c, armW * 0.28, Paint()..color = Colors.black.withOpacity(0.28));
    canvas.drawCircle(
      c,
      armW * 0.28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withOpacity(0.15),
    );

    // Arrows.
    final arrowSize = r * 0.17;
    final offset = r * 0.62;
    _drawDirectionalArrow(canvas, c - Offset(0, offset), arrowSize, _Dir.up, up);
    _drawDirectionalArrow(canvas, c + Offset(0, offset), arrowSize, _Dir.down, down);
    _drawDirectionalArrow(canvas, c - Offset(offset, 0), arrowSize, _Dir.left, left);
    _drawDirectionalArrow(canvas, c + Offset(offset, 0), arrowSize, _Dir.right, right);
  }

  void _drawDirectionalArrow(Canvas canvas, Offset center, double s, _Dir dir, bool isActive) {
    // Active states glow vividly; idle states are clean, muted semi-transparents
    final arrowPaint = Paint()
      ..color = isActive ? Colors.white : Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = isActive ? const MaskFilter.blur(BlurStyle.solid, 2) : null;

    final path = Path();
    switch (dir) {
      case _Dir.up:
        path.moveTo(center.dx, center.dy - s * 0.6);
        path.lineTo(center.dx - s, center.dy + s * 0.5);
        path.lineTo(center.dx, center.dy + s * 0.1); // Sleek chevron indentation
        path.lineTo(center.dx + s, center.dy + s * 0.5);
        break;
      case _Dir.down:
        path.moveTo(center.dx, center.dy + s * 0.6);
        path.lineTo(center.dx - s, center.dy - s * 0.5);
        path.lineTo(center.dx, center.dy - s * 0.1);
        path.lineTo(center.dx + s, center.dy - s * 0.5);
        break;
      case _Dir.left:
        path.moveTo(center.dx - s * 0.6, center.dy);
        path.lineTo(center.dx + s * 0.5, center.dy - s);
        path.lineTo(center.dx + s * 0.1, center.dy);
        path.lineTo(center.dx + s * 0.5, center.dy + s);
        break;
      case _Dir.right:
        path.moveTo(center.dx + s * 0.6, center.dy);
        path.lineTo(center.dx - s * 0.5, center.dy - s);
        path.lineTo(center.dx - s * 0.1, center.dy);
        path.lineTo(center.dx - s * 0.5, center.dy + s);
        break;
    }
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _DpadPainter oldDelegate) =>
      oldDelegate.up != up || oldDelegate.down != down || oldDelegate.left != left || oldDelegate.right != right;
}

enum _Dir { up, down, left, right }