import 'dart:async';
import 'dart:io';
import 'protocol.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// A usable local network interface (Wi-Fi, hotspot, USB tethering...).
class _LocalIf {
  final String name;
  final String address;
  final int score;
  const _LocalIf(this.name, this.address, this.score);
}

/// Owns the UDP socket used for both discovery and streaming input to the PC.
class GamepadSocket {
  RawDatagramSocket? _socket;
  String? _boundAddress;
  InternetAddress? _pcAddress;
  int _sequence = 0;
  String _deviceName = 'Phone';
  Timer? _heartbeatTimer;
  Timer? _helloTimer;
  bool _sweeping = false;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _discoveredController = StreamController<DiscoveredHost>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _activeAppController = StreamController<String>.broadcast();
  final _rumbleController = StreamController<List<int>>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<DiscoveredHost> get discoveredStream => _discoveredController.stream;

  /// Name of the PC's foreground app (process name), as reported by the host.
  Stream<String> get activeAppStream => _activeAppController.stream;

  /// Game rumble from the PC: [largeMotor, smallMotor], each 0-255.
  Stream<List<int>> get rumbleStream => _rumbleController.stream;

  /// Exposes a clean boolean stream mapped directly from the state engine
  Stream<bool> get connectionStream => _connectionController.stream;

  ConnectionStatus status = ConnectionStatus.disconnected;

  /// Computed property reflecting the real status value
  bool get isConnected => status == ConnectionStatus.connected;

  // ───────────────────────── local network ─────────────────────────

  static bool _isPrivate(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  /// 0 = ignore (mobile data, tunnels...), higher = better candidate.
  static int _score(String name, String ip) {
    final n = name.toLowerCase();
    const ignored = ['lo', 'rmnet', 'ccmni', 'pdp', 'clat', 'v4-', 'tun', 'ppp', 'dummy', 'p2p'];
    if (ignored.any((p) => n.startsWith(p))) return 0;
    var s = 1;
    const lan = ['wlan', 'swlan', 'ap', 'eth', 'rndis', 'usb', 'ncm'];
    if (lan.any((p) => n.startsWith(p))) s += 2;
    if (_isPrivate(ip)) s += 2;
    return s;
  }

  Future<List<_LocalIf>> _candidates() async {
    final out = <_LocalIf>[];
    try {
      for (final iface in await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          final ip = a.address;
          if (ip.startsWith('169.254.')) continue; // link-local, not a real network
          final sc = _score(iface.name, ip);
          if (sc > 0) out.add(_LocalIf(iface.name, ip, sc));
        }
      }
    } catch (_) {
      // NetworkInterface.list can fail on some devices/permission setups.
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// IPv4 addresses of this phone on usable (non-cellular) networks.
  Future<List<String>> localAddresses() async {
    return [for (final c in await _candidates()) c.address];
  }

  // ───────────────────────── socket ─────────────────────────

  Future<void> _bind(String? address) async {
    RawDatagramSocket? s;
    if (address != null) {
      // Binding to the Wi-Fi address forces traffic out of Wi-Fi even when
      // Android prefers mobile data because the Wi-Fi has no internet.
      try {
        s = await RawDatagramSocket.bind(InternetAddress(address), 0);
        _boundAddress = address;
      } catch (_) {
        s = null;
      }
    }
    if (s == null) {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _boundAddress = null;
    }
    s.broadcastEnabled = true;
    s.listen(_onEvent);
    _socket = s;
  }

  Future<void> _ensureSocket() async {
    if (_socket != null) return;
    final cands = await _candidates();
    await _bind(cands.isEmpty ? null : cands.first.address);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    final reply = parseReply(datagram.data);
    if (reply == null) return;

    if (reply.type == Protocol.typeDiscoverResponse && reply.hostName != null) {
      _discoveredController.add(DiscoveredHost(
        name: reply.hostName!,
        address: datagram.address.address,
      ));
    } else if (reply.type == Protocol.typeActiveApp && reply.hostName != null) {
      _activeAppController.add(reply.hostName!);
    } else if (reply.type == Protocol.typeRumble) {
      // Only trust rumble from the PC we're actually connected to.
      if (status == ConnectionStatus.connected &&
          datagram.address.address == _pcAddress?.address) {
        _rumbleController.add([reply.rumbleLarge ?? 0, reply.rumbleSmall ?? 0]);
      }
    } else if (reply.type == Protocol.typeHelloAck) {
      // HELLO is retried, so duplicate ACKs are normal: only the first counts.
      if (status != ConnectionStatus.connecting) return;
      _helloTimer?.cancel();
      if (reply.helloOk == true) {
        _setStatus(ConnectionStatus.connected);
      } else {
        _heartbeatTimer?.cancel();
        _pcAddress = null;
        _setStatus(ConnectionStatus.error);
      }
    }
  }

  /// Centralized state updates ensure the boolean stream never misses a change
  void _setStatus(ConnectionStatus s) {
    if (status == s) return;
    status = s;
    _statusController.add(s);
    _connectionController.add(s == ConnectionStatus.connected);
  }

  // ───────────────────────── discovery ─────────────────────────

  /// Looks for PCs. Combines three techniques so it works on most networks:
  /// global broadcast, directed broadcast per interface, and a unicast sweep
  /// of the local /24 (routers that drop broadcasts still pass unicast).
  /// [round] >= 2 also sweeps the neighbouring /24 blocks (for /23 networks).
  Future<void> discover({int round = 0}) async {
    final cands = await _candidates();
    final best = cands.isEmpty ? null : cands.first.address;

    // Network changed (Wi-Fi switch, hotspot on/off): rebind to the new one.
    final idle = status != ConnectionStatus.connecting &&
        status != ConnectionStatus.connected;
    if (_socket != null && idle && best != _boundAddress) {
      _socket!.close();
      _socket = null;
    }
    await _ensureSocket();

    final sock = _socket;
    if (sock == null) return;
    final packet = PacketBuilder.discover();

    final targets = <String>{'255.255.255.255'};
    for (final c in cands) {
      final b = _directedBroadcastFor(c.address);
      if (b != null) targets.add(b);
    }
    for (final t in targets) {
      try {
        sock.send(packet, InternetAddress(t), Protocol.port);
      } catch (_) {
        // A given target may be unreachable; keep trying the others.
      }
    }

    if (_sweeping) return;
    _sweeping = true;
    try {
      final spread = round >= 2 ? 1 : 0;
      final bases = _boundAddress != null
          ? [_boundAddress!]
          : [for (final c in cands) c.address];
      for (final base in bases) {
        await _sweep(base, packet, spread);
      }
    } finally {
      _sweeping = false;
    }
  }

  Future<void> _sweep(String localIp, List<int> packet, int spread) async {
    final p = localIp.split('.');
    if (p.length != 4) return;
    final c = int.tryParse(p[2]);
    final self = int.tryParse(p[3]);
    if (c == null || self == null) return;

    for (var cc = c - spread; cc <= c + spread; cc++) {
      if (cc < 0 || cc > 255) continue;
      for (var h = 1; h <= 254; h++) {
        if (cc == c && h == self) continue;
        final sock = _socket;
        if (sock == null) return;
        try {
          sock.send(packet, InternetAddress('${p[0]}.${p[1]}.$cc.$h'), Protocol.port);
        } catch (_) {}
        // Let the OS drain its send buffer so packets aren't dropped.
        if (h % 40 == 0) await Future.delayed(const Duration(milliseconds: 3));
      }
    }
  }

  String? _directedBroadcastFor(String ipv4) {
    final parts = ipv4.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  // ───────────────────────── connection ─────────────────────────

  /// Connects to a specific PC by IP address. HELLO is re-sent a few times
  /// because a single UDP packet can easily get lost on Wi-Fi.
  Future<void> connect(String ipAddress, {String deviceName = 'Phone'}) async {
    await _ensureSocket();
    _deviceName = deviceName;
    _pcAddress = InternetAddress(ipAddress);
    _setStatus(ConnectionStatus.connecting);

    void sendHello() {
      final addr = _pcAddress;
      if (addr == null) return;
      try {
        _socket?.send(PacketBuilder.hello(deviceName), addr, Protocol.port);
      } catch (_) {}
    }

    sendHello();
    _helloTimer?.cancel();
    var tries = 0;
    _helloTimer = Timer.periodic(const Duration(milliseconds: 350), (t) {
      if (status != ConnectionStatus.connecting || _pcAddress == null || ++tries > 12) {
        t.cancel();
        return;
      }
      sendHello();
    });

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_pcAddress == null) return;
      if (DateTime.now().difference(_lastSent).inMilliseconds > 500) {
        _socket?.send(PacketBuilder.heartbeat(), _pcAddress!, Protocol.port);
        _lastSent = DateTime.now();
      }
    });
  }

  /// Changes the name shown on the PC without reconnecting (re-sends HELLO;
  /// the host just updates the name of the existing player).
  void rename(String name) {
    _deviceName = name;
    final addr = _pcAddress;
    if (_socket == null || addr == null) return;
    try {
      _socket!.send(PacketBuilder.hello(name), addr, Protocol.port);
    } catch (_) {}
  }

  /// Gives up on a connection attempt that got no answer.
  void cancelConnect() {
    _helloTimer?.cancel();
    _heartbeatTimer?.cancel();
    _helloTimer = null;
    _heartbeatTimer = null;
    _pcAddress = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  /// Sends one INPUT frame.
  void sendInput({
    required int buttons,
    required double lx,
    required double ly,
    required double rx,
    required double ry,
    required double lt,
    required double rt,
  }) {
    if (_socket == null || _pcAddress == null) return;
    final packet = PacketBuilder.input(
      buttons: buttons,
      lx: lx,
      ly: ly,
      rx: rx,
      ry: ry,
      lt: lt,
      rt: rt,
      sequence: _sequence++,
    );
    _socket!.send(packet, _pcAddress!, Protocol.port);
    _lastSent = DateTime.now();
  }

  void disconnect() {
    if (_socket != null && _pcAddress != null) {
      _socket!.send(PacketBuilder.goodbye(), _pcAddress!, Protocol.port);
    }
    _helloTimer?.cancel();
    _heartbeatTimer?.cancel();
    _helloTimer = null;
    _heartbeatTimer = null;
    _pcAddress = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    _helloTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socket?.close();
    _statusController.close();
    _discoveredController.close();
    _connectionController.close();
    _activeAppController.close();
    _rumbleController.close();
  }
}
