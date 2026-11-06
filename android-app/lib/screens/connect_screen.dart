import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/gamepad_socket.dart';
import '../network/player_name.dart';
import '../network/protocol.dart';
import '../network/saved_hosts.dart';
import '../theme.dart';
import '../widgets/app_background.dart';
import 'gamepad_screen.dart';

/// One row of the PC list: either found on the network now, or remembered.
class _HostEntry {
  final String name;
  final String address;
  final bool online;
  final bool saved;
  const _HostEntry(this.name, this.address, {required this.online, required this.saved});
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> with WidgetsBindingObserver {
  final GamepadSocket _socket = GamepadSocket();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  final Map<String, DiscoveredHost> _found = {};
  final Map<String, DateTime> _lastSeen = {};
  List<SavedHost> _recent = [];
  List<String> _myAddresses = [];

  Timer? _discoverTimer;
  Timer? _clock;
  StreamSubscription<DiscoveredHost>? _discoverSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  String? _connectingTo; // address of the PC we're connecting to right now
  String? _connectingName;
  String? _lastTarget; // for "Try again"
  String? _error;
  int _round = 0;
  int _seconds = 0;
  bool _navigating = false; // a route (gamepad / editor) is on top of us
  bool _paused = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _discoverSub = _socket.discoveredStream.listen(_onHost);
    _statusSub = _socket.statusStream.listen(_onStatus);
    PlayerName.load().then((n) {
      if (mounted) _nameController.text = n;
    });
    _loadRecent();
    _startDiscovery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDiscovery();
    _discoverSub?.cancel();
    _statusSub?.cancel();
    _socket.dispose();
    _ipController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // Pause scanning in the background, rescan right away on return (the Wi-Fi
  // may have changed meanwhile).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _paused = false;
      if (!_navigating && _connectingTo == null) _startDiscovery();
    } else if (state == AppLifecycleState.paused) {
      _paused = true;
      _stopDiscovery();
    }
  }

  // ───────────────────────── discovery ─────────────────────────

  void _onHost(DiscoveredHost host) {
    if (!mounted) return;
    final old = _found[host.address];
    _lastSeen[host.address] = DateTime.now();
    if (old == null || old.name != host.name) {
      setState(() => _found[host.address] = host);
    }
  }

  void _startDiscovery() {
    if (!mounted) return;
    _stopDiscovery();
    _round = 0;
    _seconds = 0;
    _tickDiscovery();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _seconds++;
        // Drop PCs that stopped answering for a while.
        _found.removeWhere((addr, _) {
          final seen = _lastSeen[addr];
          return seen == null || now.difference(seen).inSeconds > 20;
        });
      });
    });
  }

  void _tickDiscovery() {
    if (!mounted || _paused) return;
    _socket.discover(round: _round).catchError((_) {});
    if (_round % 4 == 0) _refreshAddresses();
    _round++;
    // Fast at first, gentler afterwards to spare battery.
    _discoverTimer = Timer(Duration(milliseconds: _round < 6 ? 1500 : 4000), _tickDiscovery);
  }

  void _stopDiscovery() {
    _discoverTimer?.cancel();
    _clock?.cancel();
    _discoverTimer = null;
    _clock = null;
  }

  void _refreshAddresses() {
    _socket.localAddresses().then((addrs) {
      if (mounted && !listEquals(addrs, _myAddresses)) {
        setState(() => _myAddresses = addrs);
      }
    });
  }

  Future<void> _loadRecent() async {
    final list = await SavedHosts.load();
    if (!mounted) return;
    setState(() {
      _recent = list;
      // One tap reconnect: pre-fill the last PC's address.
      if (!_prefilled && list.isNotEmpty && _ipController.text.isEmpty) {
        _ipController.text = list.first.address;
      }
      _prefilled = true;
    });
  }

  bool _isOnline(String address) {
    final seen = _lastSeen[address];
    return seen != null && DateTime.now().difference(seen).inSeconds < 9;
  }

  // ───────────────────────── connecting ─────────────────────────

  bool _isValidIPv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255 && p.length <= 3;
    });
  }

  void _onStatus(ConnectionStatus status) {
    if (!mounted) return;
    if (status == ConnectionStatus.connected) {
      if (_navigating) return;
      _navigating = true;
      final ip = _connectingTo;
      final name = (ip != null ? _found[ip]?.name : null) ?? _connectingName ?? 'PC';
      if (ip != null) {
        SavedHosts.remember(ip, name).then((_) => _loadRecent());
      }
      setState(() {
        _connectingTo = null;
        _error = null;
      });
      _stopDiscovery();
      HapticFeedback.mediumImpact();
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => GamepadScreen(socket: _socket)))
          .then((_) {
        _navigating = false;
        if (!mounted) return;
        setState(() {
          _error = null;
          _found.clear();
          _lastSeen.clear();
        });
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        _startDiscovery();
      });
    } else if (status == ConnectionStatus.error) {
      setState(() {
        _connectingTo = null;
        _error = 'The PC refused the connection.\n'
            'Make sure ViGEmBus is installed on it (see the README).';
      });
      _startDiscovery();
    }
  }

  Future<void> _connectTo(String raw, {String? name}) async {
    final ip = raw.trim();
    if (_connectingTo != null) return;
    if (!_isValidIPv4(ip)) {
      setState(() => _error = 'Enter a valid IP address, for example 192.168.1.20');
      return;
    }
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _stopDiscovery();
    setState(() {
      _connectingTo = ip;
      _connectingName = name;
      _lastTarget = ip;
      _error = null;
    });

    try {
      final player = PlayerName.clean(_nameController.text);
      await PlayerName.save(player);
      await _socket.connect(ip, deviceName: player);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectingTo = null;
        _error = 'Could not start the connection: $e';
      });
      _startDiscovery();
      return;
    }

    Future.delayed(const Duration(milliseconds: 4500), () {
      if (!mounted || _connectingTo != ip) return;
      if (_socket.status != ConnectionStatus.connecting) return;
      _socket.cancelConnect();
      setState(() {
        _connectingTo = null;
        _error = 'No answer from $ip';
      });
      _startDiscovery();
    });
  }

  Future<void> _openEditor() async {
    if (_navigating || _connectingTo != null) return;
    HapticFeedback.selectionClick();
    _navigating = true;
    _stopDiscovery();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GamepadScreen(editorOnly: true)),
    );
    _navigating = false;
    if (!mounted) return;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _startDiscovery();
  }

  Future<void> _forget(_HostEntry e) async {
    await SavedHosts.forget(e.address);
    await _loadRecent();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    // Accept "192.168.1.20" and also "192.168.1.20:47998".
    final ip = text.split(':').first.trim();
    setState(() => _ipController.text = ip);
  }

  // ───────────────────────── UI ─────────────────────────

  List<_HostEntry> _entries() {
    final list = <_HostEntry>[
      for (final h in _found.values)
        _HostEntry(h.name, h.address, online: _isOnline(h.address), saved: false),
    ];
    for (final r in _recent) {
      if (!_found.containsKey(r.address)) {
        list.add(_HostEntry(r.name, r.address, online: false, saved: true));
      }
    }
    // Online PCs first.
    list.sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final onlineCount = entries.where((e) => e.online).length;
    final busy = _connectingTo != null;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  children: [
                    _Header(onEditLayout: _openEditor),
                    const SizedBox(height: 18),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _PlayerNameCard(
                              controller: _nameController,
                              onChanged: (v) => PlayerName.save(v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _EditorTile(onTap: _openEditor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Your PCs',
                      trailing: _ScanStatus(
                        scanning: !busy && !_paused && _discoverTimer != null,
                        found: onlineCount,
                        seconds: _seconds,
                        onRescan: busy ? null : _startDiscovery,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      _SearchingCard(
                        seconds: _seconds,
                        noNetwork: _myAddresses.isEmpty,
                        onRetry: _startDiscovery,
                      ),
                    for (final e in entries)
                      _FadeIn(
                        key: ValueKey('host-${e.address}'),
                        child: _HostCard(
                          entry: e,
                          connecting: _connectingTo == e.address,
                          enabled: !busy,
                          onTap: () => _connectTo(e.address, name: e.name),
                          onForget: e.saved ? () => _forget(e) : null,
                        ),
                      ),
                    const SizedBox(height: 22),
                    const _SectionHeader(title: 'Connect by IP'),
                    const SizedBox(height: 10),
                    _ManualEntryCard(
                      controller: _ipController,
                      connecting: busy,
                      onPaste: _paste,
                      onConnect: () => _connectTo(_ipController.text),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorCard(
                        message: _error!,
                        onRetry: (_lastTarget == null || busy)
                            ? null
                            : () => _connectTo(_lastTarget!),
                      ),
                    ],
                    if (_myAddresses.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: Text('This phone: ${_myAddresses.take(2).join(", ")}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.45), fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── widgets ─────────────────────────

/// Fades + slides its child in the first time it appears.
class _FadeIn extends StatelessWidget {
  final Widget child;
  const _FadeIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: child,
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    // Neon gradient outline (flat colour for warnings/errors) around a dark panel.
    final Gradient? frame = borderColor == null
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.activeAccent, Color(0x2200F0FF), AppColors.accent],
          )
        : null;
    return Container(
      padding: const EdgeInsets.all(1.3),
      decoration: ShapeDecoration(
        gradient: frame,
        color: frame == null ? borderColor : null,
        shape: hudShape(border: Colors.transparent, cut: 15),
        shadows: [
          BoxShadow(
              color: (borderColor ?? AppColors.activeAccent).withOpacity(0.10),
              blurRadius: 18),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: ShapeDecoration(
          color: const Color(0xEB0A0D1F),
          shape: hudShape(border: Colors.transparent, cut: 14),
        ),
        child: child,
      ),
    );
  }
}

class _Header extends StatefulWidget {
  final VoidCallback onEditLayout;
  const _Header({required this.onEditLayout});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding neon ring behind the logo.
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return Opacity(
                    opacity: (1 - t) * 0.6,
                    child: Transform.scale(
                      scale: 1 + 0.3 * t,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: ShapeDecoration(
                          shape: hudShape(border: AppColors.activeAccent, cut: 16, width: 2),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 56,
                height: 56,
                decoration: ShapeDecoration(
                  gradient: AppColors.accentGradient,
                  shape: hudShape(border: Colors.white24, cut: 16),
                  shadows: [
                    BoxShadow(
                        color: AppColors.accent.withOpacity(0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.sports_esports, color: Colors.white, size: 34),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Colors.white, AppColors.activeAccent, AppColors.accent],
                ).createShader(rect),
                child: Text('VIRTUAL GAMEPAD',
                    style: AppFonts.display(const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('PHONE  →  PC CONTROLLER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.activeAccent.withOpacity(0.85),
                            fontSize: 12.5,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entry point to the layout editor, available before connecting.
class _EditorTile extends StatelessWidget {
  final VoidCallback onTap;
  const _EditorTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shape = hudShape(border: AppColors.activeAccent.withOpacity(0.5), cut: 14);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Ink(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: ShapeDecoration(
            color: AppColors.activeAccent.withOpacity(0.10),
            shape: shape,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.activeAccent, size: 26),
              const SizedBox(height: 4),
              Text('LAYOUT',
                  style: AppFonts.display(const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title.toUpperCase(),
            style: AppFonts.display(const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3))),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ScanStatus extends StatelessWidget {
  final bool scanning;
  final int found;
  final int seconds;
  final VoidCallback? onRescan;
  const _ScanStatus({
    required this.scanning,
    required this.found,
    required this.seconds,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final label = found > 0
        ? '$found found'
        : (scanning ? 'Scanning…' : 'Stopped');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scanning && found == 0)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          )
        else
          Icon(Icons.circle,
              size: 9, color: found > 0 ? AppColors.success : Colors.white38),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        IconButton(
          tooltip: 'Scan again',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: Colors.white70,
          onPressed: onRescan,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

/// Pulsing radar shown while nothing has been found yet.
class _Radar extends StatefulWidget {
  const _Radar();

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) =>
            CustomPaint(painter: _RadarPainter(_c.value), child: child),
        child: const Center(
            child: Icon(Icons.desktop_windows_rounded, color: Colors.white, size: 22)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  _RadarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.activeAccent.withOpacity((1 - p) * 0.6);
      canvas.drawCircle(c, 12 + p * (math.min(size.width, size.height) / 2 - 12), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.t != t;
}

class _SearchingCard extends StatelessWidget {
  final int seconds;
  final bool noNetwork;
  final VoidCallback onRetry;
  const _SearchingCard({
    required this.seconds,
    required this.noNetwork,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final stuck = seconds >= 6;
    return _Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Radar(),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  noNetwork
                      ? 'No Wi-Fi network found. Join the same Wi-Fi as your PC, or turn on your hotspot / USB tethering.'
                      : 'Looking for PCs running Virtual Gamepad Host on your network…',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
          if (stuck && !noNetwork) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withOpacity(0.15), height: 1),
            const SizedBox(height: 12),
            Text(
              'Nothing yet? Check that the host app is running on the PC and that '
              'Windows Firewall allows it. Some routers block discovery (guest '
              'Wi-Fi, "AP isolation") — you can always connect by IP below.',
              style: TextStyle(color: Colors.amber.shade100, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Search again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  final _HostEntry entry;
  final bool connecting;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onForget;
  const _HostCard({
    required this.entry,
    required this.connecting,
    required this.enabled,
    required this.onTap,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final online = entry.online;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: online ? Colors.white.withOpacity(0.12) : AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: online
                      ? AppColors.success.withOpacity(0.45)
                      : AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: online
                        ? AppColors.iconBg.withOpacity(0.9)
                        : Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.desktop_windows_rounded,
                      color: Colors.white.withOpacity(online ? 1 : 0.6), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(online ? 1 : 0.8),
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 8,
                              color: online ? AppColors.success : Colors.white30),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${online ? "Online" : "Last used"} · ${entry.address}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textDim, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (connecting)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else ...[
                  if (onForget != null)
                    IconButton(
                      tooltip: 'Forget',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      color: Colors.white38,
                      onPressed: enabled ? onForget : null,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white.withOpacity(0.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerNameCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _PlayerNameCard({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.badge_rounded, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: PlayerName.maxLength,
              textInputAction: TextInputAction.done,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'PLAYER NAME',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryCard extends StatelessWidget {
  final TextEditingController controller;
  final bool connecting;
  final VoidCallback onPaste;
  final VoidCallback onConnect;
  const _ManualEntryCard({
    required this.controller,
    required this.connecting,
    required this.onPaste,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return _Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => connecting ? null : onConnect(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.dns_rounded, color: Colors.white70, size: 20),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded, size: 20, color: Colors.white70),
                onPressed: onPaste,
              ),
              hintText: '192.168.1.20',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.22),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final enabled = !connecting && value.text.trim().isNotEmpty;
              return _GradientButton(
                label: 'CONNECT',
                loading: connecting,
                onPressed: enabled ? onConnect : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const _GradientButton({required this.label, required this.loading, required this.onPressed});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final shape = hudShape(border: Colors.white30, cut: 14);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || widget.loading ? 1 : 0.45,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, child) => DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            shadows: enabled
                ? [
                    BoxShadow(
                        color: AppColors.accent.withOpacity(0.25 + 0.25 * _glow.value),
                        blurRadius: 14 + 12 * _glow.value,
                        offset: const Offset(0, 4)),
                  ]
                : null,
          ),
          child: child,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: shape,
            onTap: widget.onPressed,
            child: Ink(
              height: 52,
              decoration: ShapeDecoration(gradient: AppColors.accentGradient, shape: shape),
              child: Center(
                child: widget.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 6),
                          Text(widget.label,
                              style: AppFonts.display(const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 1.8,
                                  color: Colors.white))),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final showChecklist = message.startsWith('No answer');
    return _FadeIn(
      child: _Glass(
        borderColor: AppColors.danger.withOpacity(0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(message,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                ),
              ],
            ),
            if (showChecklist) ...[
              const SizedBox(height: 10),
              const Text(
                '• VirtualGamepadHost.exe is running on the PC\n'
                '• Phone and PC are on the same Wi-Fi\n'
                '• Windows Firewall allows the app (private + public networks)\n'
                '• UDP port 47998 is not blocked',
                style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.5),
              ),
            ],
            if (onRetry != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              children: [
                const TextSpan(text: 'Made with ❤️ by '),
                TextSpan(
                  text: 'Mohammad Kaif',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      await launchUrl(Uri.parse('https://kaif.atomprod.in'),
                          mode: LaunchMode.externalApplication);
                    },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5),
              children: [
                const TextSpan(text: 'Copyright © 2026 '),
                TextSpan(
                  text: 'Atomprod',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      await launchUrl(Uri.parse('https://atomprod.in'),
                          mode: LaunchMode.externalApplication);
                    },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
