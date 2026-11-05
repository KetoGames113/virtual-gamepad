import 'dart:async';

import '../network/gamepad_socket.dart';
import '../network/protocol.dart';


class GamepadState {
  final GamepadSocket socket;
  Timer? _ticker;

  int _buttons = 0;
  double lx = 0, ly = 0, rx = 0, ry = 0;
  double lt = 0, rt = 0;

  /// Tilt-steering overrides for the stick X axes (null = use touch stick).
  double? tiltLx, tiltRx;

  /// Right-stick override while a trigger is being slid (steer-with-trigger).
  double? trigRx, trigRy;

  GamepadState(this.socket);

  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      socket.sendInput(
        buttons: _buttons,
        lx: tiltLx ?? lx,
        ly: ly,
        rx: trigRx ?? tiltRx ?? rx,
        ry: trigRy ?? ry,
        lt: lt,
        rt: rt,
      );
    });
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Releases every button and centres every axis (used when entering the
  /// layout editor so nothing stays "held" on the PC).
  void releaseAll() {
    _buttons = 0;
    lx = ly = rx = ry = 0;
    lt = rt = 0;
    tiltLx = tiltRx = null;
    trigRx = trigRy = null;
  }

  void setButton(int bit, bool pressed) {
    if (pressed) {
      _buttons |= (1 << bit);
    } else {
      _buttons &= ~(1 << bit);
    }
  }

  void setLeftStick(double x, double y) {
    lx = x;
    ly = y;
  }

  void setRightStick(double x, double y) {
    rx = x;
    ry = y;
  }

  void setLeftTrigger(double v) => lt = v;
  void setRightTrigger(double v) => rt = v;

  // Convenience wrappers for the D-pad, which is digital-only.
  void setDpad({bool up = false, bool down = false, bool left = false, bool right = false}) {
    setButton(Protocol.bitDpadUp, up);
    setButton(Protocol.bitDpadDown, down);
    setButton(Protocol.bitDpadLeft, left);
    setButton(Protocol.bitDpadRight, right);
  }
}
