// ─────────────────────────────────────────────────────────────────────────────
// overlay/overlay_entry.dart
//
// The full-screen "Focus Lock" shown while the timer is running and GYAN is in
// the background. It runs in its own plugin-free isolate (entry `overlayMain`)
// and is driven entirely over shareData by the main isolate.
//
// Two visual states, both on the SAME always-active overlay window (so the
// foreground service — and the foreground-app monitor — never dies):
//   • LOCKED  → defaultFlag + full-screen lock UI (blocks the screen).
//   • HIDDEN  → clickThrough + fully transparent (invisible, touches pass
//               through, so an allowed app is fully usable).
//
// Messages IN  (main → overlay): refresh, mode:locked, mode:hidden
// Messages OUT (overlay → main): launch:<pkg>, exit
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../services/focus_lock_store.dart';

const _bg = Color(0xFF202225);
const _bg2 = Color(0xFF000000);
const _gold = Color(0xFFD3AD7F);
const _danger = Color(0xFFED4245);
const _avatarColors = [
  Color(0xFF5865F2), Color(0xFF57F287), Color(0xFFFF8C00),
  Color(0xFF1ABC9C), Color(0xFFE91E63), Color(0xFF9B59B6),
];

class OverlayEntryApp extends StatelessWidget {
  const OverlayEntryApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _OverlayScreen(),
      );
}

class _OverlayScreen extends StatefulWidget {
  const _OverlayScreen();
  @override
  State<_OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<_OverlayScreen>
    with WidgetsBindingObserver {
  DateTime? _endTime;
  int _remainingSecs = 0;
  int _totalSecs = 1;
  String _subjectName = '';
  List<AllowedApp> _allowed = [];
  List<AllowedApp> _catalog = [];
  bool _managing = false;
  bool _hidden = false; // shrunk to a 1px click-through window in allowed apps
  double _fullH = 900; // captured full height (dp) to grow back to
  Timer? _ticker;

  static const String _kEnd = 'timer_overlay_end_time';
  static const String _kSubject = 'timer_overlay_subject';
  static const String _kTotal = 'timer_overlay_total';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Poll the file channel: refresh the countdown + lists, and apply the
    // lock/hide mode the main isolate writes. (shareData is unreliable here.)
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  // When the main isolate re-shows this (cached) overlay to re-lock over a
  // non-allowed app, the engine resumes — snap straight back to the locked
  // view and reload, instead of flashing the previous hidden frame.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {
        _hidden = false;
        _managing = false;
      });
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  // ── Visual mode ─────────────────────────────────────────────────────────────
  // While an allowed app is open we shrink to a small floating timer "bubble"
  // (not invisible — a fully hidden overlay gets its Flutter engine paused by
  // Android and can never grow back, and the service can't be restarted from
  // the background). The little bubble keeps the engine alive so the poll can
  // grow the lock straight back the moment a non-allowed app appears.
  Future<void> _setHidden(bool hidden) async {
    if (hidden == _hidden) return;
    if (mounted) setState(() => _hidden = hidden);
    try {
      if (hidden) {
        await FlutterOverlayWindow.resizeOverlay(168, 52, false);
      } else {
        await FlutterOverlayWindow.resizeOverlay(-1, _fullH.toInt(), false);
      }
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    } catch (_) {}
  }

  // ── Load timer + app lists (once, on first show) ────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // this isolate caches prefs; read what main just wrote
    final endStr = prefs.getString(_kEnd);
    _subjectName = prefs.getString(_kSubject) ?? '';
    _totalSecs = prefs.getInt(_kTotal) ?? 1;
    _allowed = await FocusLockStore.loadApps();
    _catalog = await FocusLockStore.loadCatalog();
    _endTime = (endStr != null) ? DateTime.tryParse(endStr) : null;
    if (mounted) setState(() {});
  }

  int _pollCount = 0;
  Future<void> _poll() async {
    // Countdown every tick.
    if (_endTime != null && mounted) {
      setState(() =>
          _remainingSecs = math.max(0, _endTime!.difference(DateTime.now()).inSeconds));
    }
    // Apply lock/hide mode the main isolate decided.
    final mode = await FocusLockStore.readMode();
    await _setHidden(mode == 'hidden');
    // Every ~2s re-read end time + lists (covers a re-shown cached engine and
    // newly-allowed apps) without hammering the disk.
    if (_pollCount++ % 4 == 0) await _load();
  }

  // ── Actions → written to the file channel for the main isolate ──────────────
  Future<void> _openApp(AllowedApp a) async {
    await _setHidden(true); // get out of the way immediately
    await FocusLockStore.writeCommand('launch:${a.package}');
  }

  void _exit() => FocusLockStore.writeCommand('exit');

  void _toggleAllowed(AllowedApp app) {
    setState(() {
      _allowed = _allowed.any((a) => a.package == app.package)
          ? _allowed.where((a) => a.package != app.package).toList()
          : [..._allowed, app];
    });
    FocusLockStore.saveApps(_allowed);
  }

  String get _time {
    final m = _remainingSecs ~/ 60;
    final s = _remainingSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Remember the full height (dp) while the window is full, so _setHidden can
    // grow back to exactly this after a 1px hidden phase.
    final h = MediaQuery.sizeOf(context).height;
    if (h > 400) _fullH = h;

    // Hidden: the small floating timer bubble (window itself is bubble-sized).
    if (_hidden) return _bubbleView();

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    // Overlay windows don't report safe-area insets, so clear the status bar /
    // camera cutout manually (generous, since cutouts vary by device).
    final topInset = math.max(MediaQuery.viewPaddingOf(context).top, 56.0);
    final botInset = math.max(MediaQuery.viewPaddingOf(context).bottom, 20.0);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg, _bg2],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: topInset, bottom: botInset),
          child: _managing ? _manageView() : _lockView(),
        ),
      ),
    );
  }

  // ── Bubble (small floating timer shown while in an allowed app) ─────────────
  Widget _bubbleView() {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: _exit, // tap the bubble to jump back to GYAN's timer
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _bg.withOpacity(0.95),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _gold.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_clock_rounded, color: _gold, size: 18),
            const SizedBox(width: 8),
            Text(_time,
                style: GoogleFonts.inder(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ]),
          ),
        ),
      ),
    );
  }

  // ── Lock view ───────────────────────────────────────────────────────────────
  Widget _lockView() {
    final progress =
        _totalSecs <= 0 ? 0.0 : (_remainingSecs / _totalSecs).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(children: [
        const SizedBox(height: 14),
        _badge(),
        const SizedBox(height: 28),

        // Countdown ring
        SizedBox(
          width: 184,
          height: 184,
          child: CustomPaint(
            painter: _RingPainter(progress),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_time,
                    style: GoogleFonts.inder(
                        color: Colors.white,
                        fontSize: 46,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                if (_subjectName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inder(color: _gold, fontSize: 12)),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 28),

        Text('Only your allowed apps can be opened\nwhile the timer is running.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inder(
                color: Colors.white70, fontSize: 14, height: 1.4)),
        const SizedBox(height: 26),

        // Allowed apps grid
        Flexible(
          child: _allowed.isEmpty
              ? Center(
                  child: Text(
                      'No allowed apps yet.\nTap “Manage apps” to add some.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inder(
                          color: Colors.white38, fontSize: 13, height: 1.5)))
              : SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 20,
                    children: _allowed
                        .map((a) => _appTile(a, 58, () => _openApp(a)))
                        .toList(),
                  ),
                ),
        ),
        const Spacer(),

        // Manage
        GestureDetector(
          onTap: () => setState(() => _managing = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tune_rounded, color: _gold, size: 16),
              const SizedBox(width: 7),
              Text('Manage apps',
                  style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 14),

        // Exit
        GestureDetector(
          onTap: _exit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _danger,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: _danger.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Exit Focus Lock',
                  style: GoogleFonts.inder(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text('Back to GYAN — your timer keeps running',
            style: GoogleFonts.inder(color: Colors.white24, fontSize: 11)),
      ]),
    );
  }

  // ── Manage view (select allowed apps, grid) ─────────────────────────────────
  Widget _manageView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Allowed apps',
              style: GoogleFonts.inder(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _managing = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                  color: _gold, borderRadius: BorderRadius.circular(22)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_rounded, color: _bg, size: 18),
                const SizedBox(width: 5),
                Text('Done',
                    style: GoogleFonts.inder(
                        color: _bg,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Tap an app to allow or block it during a focus lock.',
            style: GoogleFonts.inder(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 14),
        Expanded(
          child: _catalog.isEmpty
              ? Center(
                  child: Text('Open GYAN once so it can load your apps',
                      style: GoogleFonts.inder(
                          color: Colors.white38, fontSize: 13)))
              : GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _catalog.length,
                  itemBuilder: (_, i) {
                    final app = _catalog[i];
                    final on = _allowed.any((a) => a.package == app.package);
                    return _appTile(app, 54, () => _toggleAllowed(app),
                        selected: on);
                  },
                ),
        ),
      ]),
    );
  }

  // ── Bits ──────────────────────────────────────────────────────────────────────
  Widget _badge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _gold.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_rounded, color: _gold, size: 15),
          const SizedBox(width: 7),
          Text('Focus Lock',
              style: GoogleFonts.inder(
                  color: _gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ]),
      );

  /// App tile: icon + name, with an optional selected check (manage view).
  Widget _appTile(AllowedApp a, double iconSize, VoidCallback onTap,
      {bool? selected}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: iconSize + 16,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            _icon(a, iconSize),
            if (selected != null)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  decoration: BoxDecoration(
                      color: _bg, shape: BoxShape.circle),
                  child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      color: selected ? _gold : Colors.white38,
                      size: 20),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inder(color: Colors.white70, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _icon(AllowedApp app, double size) {
    if (app.iconB64.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.memory(base64Decode(app.iconB64),
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true),
        );
      } catch (_) {/* letter fallback */}
    }
    final letter = app.name.isNotEmpty ? app.name[0].toUpperCase() : '?';
    final color =
        _avatarColors[app.name.hashCode.abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(letter,
          style: GoogleFonts.inder(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white.withOpacity(0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = _gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
