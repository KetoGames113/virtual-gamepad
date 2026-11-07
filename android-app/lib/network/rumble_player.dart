import 'dart:async';
import 'dart:math' as math;

import 'package:vibration/vibration.dart';

/// Turns the PC's game rumble (XInput motor speeds) into phone vibration.
///
/// The PC re-sends the current rumble every ~150 ms while it is active, and a
/// watchdog here stops the motor if the packets stop, so a lost "stop" packet
/// can never leave the phone buzzing.
class RumblePlayer {
  bool _ready = false;
  bool _hasVibrator = false;
  bool _hasAmplitude = false;
  Timer? _watchdog;
  int _lastAmp = 0;
  DateTime _lastPulse = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    try {
      _hasVibrator = (await Vibration.hasVibrator()) == true;
      _hasAmplitude =
          _hasVibrator && ((await Vibration.hasAmplitudeControl()) == true);
    } catch (_) {
      _hasVibrator = false;
      _hasAmplitude = false;
    }
    _ready = true;
  }

  /// [large] / [small]: motor speeds 0-255. [strength]: user setting 0..1
  /// (0 = rumble off).
  void update(int large, int small, double strength) {
    if (!_ready || !_hasVibrator || strength <= 0) {
      stop();
      return;
    }
    // The heavy motor dominates; the light one adds a lighter buzz.
    final level = (math.max(large.toDouble(), small * 0.8) / 255) * strength;
    if (level < 0.02) {
      stop();
      return;
    }
    final int amp = (level * 255).round().clamp(1, 255).toInt();

    _watchdog?.cancel();
    _watchdog = Timer(const Duration(milliseconds: 450), stop);

    // Start a new pulse only when the level changed or the last one is
    // about to end (each pulse lasts 400 ms).
    final now = DateTime.now();
    if ((amp - _lastAmp).abs() < 12 &&
        now.difference(_lastPulse).inMilliseconds < 250) {
      return;
    }
    _lastAmp = amp;
    _lastPulse = now;

    if (_hasAmplitude) {
      Vibration.vibrate(duration: 400, amplitude: amp);
    } else if (amp >= 60) {
      // No intensity control on this phone: it's full power or nothing.
      Vibration.vibrate(duration: 400);
    }
  }

  void stop() {
    _watchdog?.cancel();
    _watchdog = null;
    if (_lastAmp != 0) {
      _lastAmp = 0;
      if (_hasVibrator) Vibration.cancel();
    }
  }

  void dispose() => stop();
}
