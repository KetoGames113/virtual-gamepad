import 'package:flutter/material.dart';

import '../models/layout_store.dart';
import '../theme.dart';

/// Small text-input dialog. Returns the trimmed text, or null if cancelled.
Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String hint = '',
  int maxLength = 40,
}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
  ctrl.dispose();
  return (r == null || r.isEmpty) ? null : r;
}

/// The layout-editor overlay.
///
///  * a slim **dock** (Done · profile · undo · grid · hidden controls · settings)
///  * an **inspector** for the selected control (size, opacity, colour, nudge,
///    hide) with an expandable "More settings" section
///  * a **settings dialog** with General / Tilt / Gyro / Games tabs
///
/// It sits at the top of the screen, or at the bottom when the selected control
/// is in the upper half, so it never covers what you are editing.
class LayoutEditor extends StatefulWidget {
  final LayoutStore layout;
  final String? selected;
  final ValueChanged<String?> onSelect;

  final bool snap;
  final ValueChanged<bool> onSnap;

  final VoidCallback onDone;

  /// Moves the selected control by this many logical pixels.
  final void Function(double dx, double dy) onNudge;

  final String? lastApp;
  final ValueNotifier<double> tiltPreview;
  final VoidCallback onCalibrate;
  final VoidCallback onBeginAutoCal;
  final VoidCallback onApplyAutoProfile;
  final VoidCallback onRenamePlayer;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final void Function(String name) onAddGame;
  final VoidCallback onBuzz;

  const LayoutEditor({
    super.key,
    required this.layout,
    required this.selected,
    required this.onSelect,
    required this.snap,
    required this.onSnap,
    required this.onDone,
    required this.onNudge,
    required this.lastApp,
    required this.tiltPreview,
    required this.onCalibrate,
    required this.onBeginAutoCal,
    required this.onApplyAutoProfile,
    required this.onRenamePlayer,
    required this.onCopy,
    required this.onPaste,
    required this.onAddGame,
    required this.onBuzz,
  });

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  bool _advanced = false;
  String? _lastSelected;

  LayoutStore get _l => widget.layout;

  static const _small = TextStyle(color: Colors.white70, fontSize: 12);
  static const _hint = TextStyle(color: Colors.white38, fontSize: 10);

  static const List<int> _palette = [
    0xFF7C3AED, 0xFF00BFFF, 0xFF00FF85, 0xFFFF1744, 0xFFFFD600,
    0xFFFF9100, 0xFFFF2ED1, 0xFF546E7A, 0xFF212121, 0xFFFFFFFF,
  ];

  // ───────────────────────── building blocks ─────────────────────────

  Widget _hud({required Widget child, EdgeInsets padding = const EdgeInsets.all(10)}) {
    return Material(
      color: const Color(0xF2070A18),
      shape: hudShape(border: AppColors.activeAccent.withOpacity(0.45), cut: 14),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String Function(double v)? fmt,
    double labelWidth = 52,
    double valueWidth = 40,
  }) {
    return Row(
      children: [
        SizedBox(width: labelWidth, child: Text(label, style: _small)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChangeStart: (_) => _l.checkpoint(group: 'slider:$label'),
              onChanged: onChanged,
              onChangeEnd: (_) => _l.save(),
            ),
          ),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(fmt != null ? fmt(value) : '${(value * 100).round()}%',
              textAlign: TextAlign.end, style: _small),
        ),
      ],
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged, {String? hint}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _small),
        const SizedBox(width: 6),
        Switch(
          value: value,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            _l.checkpoint();
            onChanged(v);
            _l.save();
          },
        ),
        if (hint != null) Flexible(child: Text(hint, style: _hint)),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap,
      {bool active = false, Color? color}) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      iconSize: 22,
      color: active ? AppColors.activeAccent : (color ?? Colors.white70),
      disabledColor: Colors.white24,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }

  // ───────────────────────── dock ─────────────────────────

  Widget _profileMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Profiles',
      color: const Color(0xFF12152B),
      onSelected: _onProfileAction,
      itemBuilder: (_) => [
        for (final n in _l.profileNames)
          PopupMenuItem(
            value: 'p:$n',
            child: Row(children: [
              Icon(n == _l.active ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16, color: AppColors.activeAccent),
              const SizedBox(width: 8),
              Text(n),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'new', child: Text('New profile (copy of this)')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (_l.canDeleteActive)
          const PopupMenuItem(value: 'delete', child: Text('Delete this profile')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers, size: 18, color: AppColors.activeAccent),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(_l.active,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Future<void> _onProfileAction(String v) async {
    if (v.startsWith('p:')) {
      _l.switchTo(v.substring(2));
      _l.save();
      widget.onSelect(null);
    } else if (v == 'new') {
      final n = await askText(context, 'New profile (copy of current)', hint: 'Profile name');
      if (n == null) return;
      _l.createProfile(n);
      _l.save();
    } else if (v == 'rename') {
      final n = await askText(context, 'Rename profile', initial: _l.active, hint: 'Profile name');
      if (n == null) return;
      _l.renameActive(n);
      _l.save();
    } else if (v == 'delete') {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${_l.active}"?'),
          content: const Text('This profile and its layout will be removed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) {
        _l.deleteActive();
        _l.save();
      }
    }
  }

  Widget _hiddenMenu() {
    final hidden = [
      for (final s in LayoutStore.specs)
        if (s.canHide && !_l.of(s.id).visible) s
    ];
    return PopupMenuButton<String>(
      tooltip: 'Hidden controls',
      enabled: hidden.isNotEmpty,
      color: const Color(0xFF12152B),
      onSelected: (id) {
        _l.checkpoint();
        _l.setVisible(id, true);
        _l.save();
        widget.onSelect(id);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(enabled: false, child: Text('Tap to bring back', style: _hint)),
        for (final s in hidden)
          PopupMenuItem(
            value: s.id,
            child: Row(children: [
              const Icon(Icons.visibility, size: 16, color: AppColors.activeAccent),
              const SizedBox(width: 8),
              Text(s.title),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Badge(
          isLabelVisible: hidden.isNotEmpty,
          label: Text('${hidden.length}'),
          child: Icon(Icons.visibility_off,
              size: 22, color: hidden.isEmpty ? Colors.white24 : Colors.white70),
        ),
      ),
    );
  }

  Widget _dock() {
    return _hud(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: widget.onDone,
              icon: const Icon(Icons.check, size: 18),
              label: Text('DONE',
                  style: AppFonts.display(
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ),
            const SizedBox(width: 4),
            _profileMenu(),
            _iconBtn(Icons.undo, 'Undo', _l.canUndo ? () {
              _l.undo();
              _l.save();
            } : null),
            _iconBtn(Icons.grid_4x4, 'Snap to grid', () => widget.onSnap(!widget.snap),
                active: widget.snap),
            _hiddenMenu(),
            _iconBtn(Icons.settings, 'Settings', _openSettings),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── inspector ─────────────────────────

  Widget _swatch(String id, int? argb, ItemLayout it) {
    final selected = it.color == argb;
    return GestureDetector(
      onTap: () {
        _l.checkpoint();
        _l.setColor(id, argb);
        _l.save();
      },
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: argb == null ? Colors.transparent : Color(argb),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: argb == null ? const Icon(Icons.block, size: 13, color: Colors.white54) : null,
      ),
    );
  }

  Widget _nudgePad() {
    Widget b(IconData i, double dx, double dy) => InkResponse(
          radius: 18,
          onTap: () {
            _l.checkpoint(group: 'nudge');
            widget.onNudge(dx, dy);
          },
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(i, size: 20, color: Colors.white70),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Nudge', style: _small),
        const SizedBox(width: 4),
        b(Icons.arrow_back, -4, 0),
        b(Icons.arrow_upward, 0, -4),
        b(Icons.arrow_downward, 0, 4),
        b(Icons.arrow_forward, 4, 0),
      ],
    );
  }

  Widget _inspector(String id) {
    final spec = _l.spec(id);
    final it = _l.of(id);
    return _hud(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(spec.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.display(const TextStyle(
                        color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
              ),
              TextButton(
                onPressed: () {
                  _l.resetItem(id);
                  _l.save();
                },
                child: const Text('Reset'),
              ),
              if (spec.canHide)
                TextButton.icon(
                  onPressed: () {
                    _l.checkpoint();
                    _l.setVisible(id, !it.visible);
                    _l.save();
                  },
                  icon: Icon(it.visible ? Icons.visibility_off : Icons.visibility, size: 18),
                  label: Text(it.visible ? 'Hide' : 'Show'),
                ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: Colors.white70,
                icon: const Icon(Icons.close),
                onPressed: () => widget.onSelect(null),
              ),
            ],
          ),
          if (!it.visible)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('Hidden while playing — it still shows faded here so you can bring it back.',
                  style: _hint),
            ),
          Row(
            children: [
              Expanded(
                child: _slider('Size', it.scale, LayoutStore.minScale, LayoutStore.maxScale,
                    (v) => _l.setScale(id, v)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _slider('Opacity', it.opacity, LayoutStore.minOpacity, 1.0,
                    (v) => _l.setOpacity(id, v)),
              ),
            ],
          ),
          Row(
            children: [
              _nudgePad(),
              const SizedBox(width: 10),
              if (spec.canColor)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _swatch(id, null, it),
                        for (final c in _palette) _swatch(id, c, it),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
          if (_hasAdvanced(id))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_advanced ? 'Fewer settings' : 'More settings'),
              ),
            ),
          if (_advanced && _hasAdvanced(id)) ..._advancedFor(id),
        ],
      ),
    );
  }

  static const _toggleIds = {
    'lb', 'rb', 'l3', 'r3', 'back', 'guide', 'start',
    'btn_a', 'btn_b', 'btn_x', 'btn_y',
  };

  bool _hasAdvanced(String id) =>
      id == 'lstick' || id == 'rstick' || id == 'lt' || id == 'rt' || _toggleIds.contains(id);

  List<Widget> _advancedFor(String id) {
    final st = _l.settings;
    final isLeft = id == 'lstick' || id == 'lt';
    final out = <Widget>[];

    if (id == 'lstick' || id == 'rstick') {
      final left = id == 'lstick';
      out.addAll([
        Row(children: [
          Expanded(
            child: _slider('Sensitivity', left ? st.sensL : st.sensR,
                LayoutStore.minSensitivity, LayoutStore.maxSensitivity,
                (v) => _l.setSensitivity(left, v),
                labelWidth: 74, valueWidth: 44),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _slider('Deadzone', left ? st.deadzoneL : st.deadzoneR, 0,
                LayoutStore.maxDeadzone, (v) => _l.setDeadzone(left, v),
                labelWidth: 74),
          ),
        ]),
        Row(children: [
          Expanded(
            child: _slider('Curve', left ? st.curveL : st.curveR, LayoutStore.minCurve,
                LayoutStore.maxCurve, (v) => _l.tweak((s) {
                      if (left) {
                        s.curveL = v;
                      } else {
                        s.curveR = v;
                      }
                    }),
                fmt: (v) => '${v.toStringAsFixed(1)}×', labelWidth: 74, valueWidth: 44),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _slider('Y gain', left ? st.yScaleL : st.yScaleR, LayoutStore.minYScale,
                LayoutStore.maxYScale, (v) => _l.tweak((s) {
                      if (left) {
                        s.yScaleL = v;
                      } else {
                        s.yScaleR = v;
                      }
                    }),
                labelWidth: 74),
          ),
        ]),
        _switchRow('Floating (appears where you touch)', _l.isFloating(id),
            (v) => _l.setFloating(id, v)),
        if (left)
          _switchRow('Auto-sprint', st.autoSprint, (v) => _l.tweak((s) => s.autoSprint = v),
              hint: 'clicks L3 when pushed fully forward'),
      ]);
    }

    if (id == 'lt' || id == 'rt') {
      final latch = isLeft ? st.latchLt : st.latchRt;
      final aim = isLeft ? st.aimLt : st.aimRt;
      out.addAll([
        Row(children: [
          _switchRow('Double-tap lock', latch, (v) => _l.setLatch(isLeft, v)),
          Expanded(
            child: latch
                ? _slider('Lock at', isLeft ? st.latchLevelLt : st.latchLevelRt,
                    LayoutStore.minLatchLevel, 1.0, (v) => _l.tweak((s) {
                          if (isLeft) {
                            s.latchLevelLt = v;
                          } else {
                            s.latchLevelRt = v;
                          }
                        }),
                    labelWidth: 56)
                : const Text('tap again to release', style: _hint),
          ),
        ]),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _switchRow('Slide to steer (right stick)', isLeft ? st.steerLt : st.steerRt,
                (v) => _l.setSteer(isLeft, v)),
            _switchRow('Aim & fire', aim, (v) => _l.tweak((s) {
                  if (isLeft) {
                    s.aimLt = v;
                  } else {
                    s.aimRt = v;
                  }
                })),
          ],
        ),
        if (aim) ...[
          _slider('Fire pull', st.aimFire, LayoutStore.minAimFire, LayoutStore.maxAimFire,
              (v) => _l.tweak((s) => s.aimFire = v),
              fmt: (v) => '${v.toStringAsFixed(1)}×', labelWidth: 74, valueWidth: 44),
          _switchRow('Turbo (rapid fire)', st.turbo.contains(id), (v) {
            _l.tweak((s) => v ? s.turbo.add(id) : s.turbo.remove(id));
          }, hint: 'repeats the press while you hold the pull'),
        ],
        const Text('Aim & fire: touch = aim with the right stick, pull further = full press.',
            style: _hint),
      ]);
    }

    if (_toggleIds.contains(id)) {
      out.add(Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _switchRow('Toggle (tap on / tap off)', st.toggles.contains(id), (v) {
            _l.tweak((s) => v ? s.toggles.add(id) : s.toggles.remove(id));
          }),
          _switchRow('Turbo (rapid fire)', st.turbo.contains(id), (v) {
            _l.tweak((s) => v ? s.turbo.add(id) : s.turbo.remove(id));
          }),
        ],
      ));
    }
    return out;
  }

  // ───────────────────────── settings dialog ─────────────────────────

  void _openSettings() {
    int tab = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0B0F1E),
        shape: hudShape(border: AppColors.activeAccent.withOpacity(0.4)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.of(ctx).size.height * 0.92,
          ),
          child: StatefulBuilder(
            builder: (ctx, setDlg) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('SETTINGS',
                            style: AppFonts.display(const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.4))),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final e in const [
                          (0, 'General'),
                          (1, 'Tilt steering'),
                          (2, 'Gyro aim'),
                          (3, 'Games'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(e.$2),
                              selected: tab == e.$1,
                              onSelected: (_) => setDlg(() => tab = e.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: ListenableBuilder(
                        listenable: _l,
                        builder: (_, __) => switch (tab) {
                          0 => _generalTab(),
                          1 => _tiltTab(),
                          2 => _gyroTab(),
                          _ => _gamesTab(),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _generalTab() {
    final st = _l.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vibration', style: _small),
        Wrap(
          spacing: 6,
          children: [
            for (final e in const [(0, 'Off'), (1, 'Light'), (2, 'Strong')])
              ChoiceChip(
                label: Text(e.$2),
                selected: st.haptics == e.$1,
                onSelected: (_) {
                  _l.setHaptics(e.$1);
                  _l.save();
                  widget.onBuzz(); // feel the new strength right away
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        _slider('Game rumble', st.rumble, 0, 1, (v) => _l.tweak((s) => s.rumble = v),
            labelWidth: 92,
            valueWidth: 44,
            fmt: (v) => v <= 0 ? 'Off' : '${(v * 100).round()}%'),
        const Text('The phone vibrates when the game rumbles (needs the updated PC app).',
            style: _small),
        const SizedBox(height: 6),
        _slider('Turbo speed', st.turboRate, LayoutStore.minTurboRate,
            LayoutStore.maxTurboRate, (v) => _l.tweak((s) => s.turboRate = v),
            labelWidth: 92, valueWidth: 56, fmt: (v) => '${v.round()}/s'),
        const Text('How fast rapid-fire buttons and triggers repeat the press.',
            style: _small),
        _switchRow('Show ping', st.showPing, (v) => _l.tweak((s) => s.showPing = v),
            hint: 'small badge with the connection delay while playing'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onRenamePlayer,
              icon: const Icon(Icons.badge, size: 18),
              label: const Text('Player name'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onCopy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy layout'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onPaste,
              icon: const Icon(Icons.paste, size: 18),
              label: const Text('Paste layout'),
            ),
            OutlinedButton.icon(
              onPressed: _confirmResetAll,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset this profile'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmResetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this profile?'),
        content: const Text(
            'All controls and stick settings in this profile go back to the defaults. You can undo it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      _l.resetAll();
      _l.save();
      widget.onSelect(null);
    }
  }

  Widget _tiltMeter() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.tiltPreview,
      builder: (context, v, _) => SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, bc) {
            final w = bc.maxWidth;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                Positioned(
                  left: w / 2 - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const ColoredBox(color: Colors.white38),
                ),
                Positioned(
                  left: (w - 14) * ((v.clamp(-1.0, 1.0) + 1) / 2),
                  top: 0,
                  width: 14,
                  height: 14,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.activeAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tiltTab() {
    final st = _l.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _switchRow('Tilt steering', st.tilt, (v) => _l.tweak((s) => s.tilt = v)),
            _switchRow('Invert', st.tiltInvert, (v) => _l.tweak((s) => s.tiltInvert = v)),
          ],
        ),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Controls', style: _small),
            for (final e in const [(false, 'Left stick X'), (true, 'Right stick X')])
              ChoiceChip(
                label: Text(e.$2),
                selected: st.tiltRightStick == e.$1,
                onSelected: (_) {
                  _l.tweak((s) => s.tiltRightStick = e.$1);
                  _l.save();
                },
              ),
            TextButton.icon(
              onPressed: st.tilt ? widget.onCalibrate : null,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Set center'),
            ),
          ],
        ),
        _slider('Sensitivity', st.tiltSens, LayoutStore.minTiltSens, LayoutStore.maxTiltSens,
            (v) => _l.tweak((s) => s.tiltSens = v),
            fmt: (v) => '${(45 / v).round()}°', labelWidth: 74),
        _slider('Deadzone', st.tiltDeadzone, 0, LayoutStore.maxTiltDeadzone,
            (v) => _l.tweak((s) => s.tiltDeadzone = v),
            fmt: (v) => '${v.round()}°', labelWidth: 74),
        _slider('Smoothing', st.tiltSmooth, 0, 0.9, (v) => _l.tweak((s) => s.tiltSmooth = v),
            labelWidth: 74),
        _slider('Curve', st.tiltCurve, LayoutStore.minCurve, LayoutStore.maxCurve,
            (v) => _l.tweak((s) => s.tiltCurve = v),
            fmt: (v) => '${v.toStringAsFixed(1)}×', labelWidth: 74, valueWidth: 44),
        Row(
          children: [
            Flexible(
              child: _switchRow('Auto-center on start', st.tiltAuto, (v) {
                _l.tweak((s) => s.tiltAuto = v);
                if (v) widget.onBeginAutoCal();
              }),
            ),
            const SizedBox(width: 12),
            if (st.tilt) Expanded(child: _tiltMeter()),
          ],
        ),
        const Text(
          'Hold the phone like a steering wheel. The degrees next to Sensitivity = how far you turn for full lock.',
          style: _hint,
        ),
      ],
    );
  }

  Widget _gyroTab() {
    final st = _l.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _switchRow('Gyro aim (right stick)', st.gyro, (v) => _l.tweak((s) => s.gyro = v)),
            _switchRow('Invert Y', st.gyroInvertY, (v) => _l.tweak((s) => s.gyroInvertY = v)),
          ],
        ),
        _slider('Sensitivity', st.gyroSens, LayoutStore.minTiltSens, LayoutStore.maxTiltSens,
            (v) => _l.tweak((s) => s.gyroSens = v),
            fmt: (v) => '${v.toStringAsFixed(1)}×', labelWidth: 74, valueWidth: 44),
        const Text(
          'Turn the phone left/right and tilt it up/down to aim. It adds to the right stick, so you can still use the touch stick.',
          style: _hint,
        ),
      ],
    );
  }

  Widget _gamesTab() {
    final st = _l.settings;
    final last = widget.lastApp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchRow('Auto-switch profile by game', _l.autoSwitch, (v) {
          _l.setAutoSwitch(v);
          widget.onApplyAutoProfile();
        }),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: last == null ? null : () => widget.onAddGame(last),
              icon: const Icon(Icons.add, size: 18),
              label: Text(last == null
                  ? 'No game detected'
                  : 'Use "${LayoutStore.normApp(last)}" for "${_l.active}"'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final n = await askText(context, 'Game process name (e.g. blur)',
                    hint: 'Process name');
                if (n != null) widget.onAddGame(n);
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Add by name'),
            ),
          ],
        ),
        if (st.games.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              children: [
                for (final g in st.games)
                  InputChip(
                    label: Text(g, style: const TextStyle(fontSize: 12)),
                    onDeleted: () {
                      _l.removeGame(g);
                      _l.save();
                    },
                  ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Needs the updated PC app. Games listed here switch to this profile when they come to the front.',
            style: _hint,
          ),
        ),
      ],
    );
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final id = widget.selected;
    if (id != _lastSelected) {
      _lastSelected = id;
      _advanced = false; // each control starts with the simple view
    }
    final it = id == null ? null : _l.of(id);
    final atTop = it == null || it.y > 0.5; // keep clear of the control being edited

    final dock = _dock();
    final inspector = id == null
        ? _hud(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text('Drag a control to move it  •  tap it to edit', style: _small),
          )
        : _inspector(id);

    final children = atTop
        ? [dock, const SizedBox(height: 6), inspector]
        : [inspector, const SizedBox(height: 6), dock];

    return Positioned(
      top: atTop ? 6 : null,
      bottom: atTop ? null : 6,
      left: 0,
      right: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.of(context).size.height - 12,
          ),
          // Absorb touches so they don't fall through to controls underneath.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SingleChildScrollView(
              reverse: !atTop,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
