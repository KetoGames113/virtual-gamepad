import 'dart:async';

import '../network/gamepad_socket.dart';
import '../network/protocol.dart';


class GamepadState {
  final GamepadSocket socket;
  Timer? _ticker;

  int _buttons = 0;
  double lx = 0, ly = 0, rx = 0, ry = 0;
  double lt = 0, rt = 0;

  GamepadState(this.socket);

  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      socket.sendInput(
        buttons: _buttons,
        lx: lx,
        ly: ly,
        rx: rx,
        ry: ry,
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
