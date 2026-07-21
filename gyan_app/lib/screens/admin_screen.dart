// ─────────────────────────────────────────────────────────────────────────────
// screens/admin_screen.dart
//
// Admin Panel — only reachable by eligible admins:
//   • Root admins  → email listed in config/admin_config.dart (verified email).
//   • Granted admins → flagged in Firestore (`admins/{uid}`) by a root admin.
//
// The panel re-checks isAdmin on every build (defence in depth), so even if it
// were pushed some other way, a non-admin only ever sees "Access denied".
//
// Capabilities (all self-scoped or already-permitted — no user privacy is
// exposed beyond aggregate counts):
//   • Configure Pomodoro / break durations (this device only).
//   • Override own headline stats (streak / sessions / study time).
//   • View registered + active user counts.
//   • Unlimited groups + unlocked AI (handled in the provider).
//   • Root admins: grant / revoke admin for other accounts by email.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

const _accent = Color(0xFF5865F2);

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  // Timer config (local, editable; committed on "Save").
  late int _focus, _short, _long, _cycles;

  // Stat override fields.
  final _streakCtrl = TextEditingController();
  final _bestCtrl = TextEditingController();
  final _sessionsCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();

  // Grant-admin + test-notification fields.
  final _grantCtrl = TextEditingController();
  final _testEmailCtrl = TextEditingController();

  // Aggregate metrics.
  int? _registered;
  int? _active;
  int? _paid;
  bool _loadingCounts = true;
  bool _purging = false;

  @override
  void initState() {
    super.initState();
    final prov = context.read<AppProvider>();
    _focus = prov.focusSecs;
    _short = prov.shortBreakSecs;
    _long = prov.longBreakSecs;
    _cycles = prov.cyclesPerSession;
    _fillStatFields(prov);
    _loadCounts();
  }

  void _fillStatFields(AppProvider prov) {
    _streakCtrl.text = '${prov.currentStreakDays}';
    _bestCtrl.text = '${prov.bestStreakDays}';
    _sessionsCtrl.text = '${prov.totalSessionsCount}';
    _minutesCtrl.text = '${prov.totalMinutesAllTime}';
  }

  @override
  void dispose() {
    _streakCtrl.dispose();
    _bestCtrl.dispose();
    _sessionsCtrl.dispose();
    _minutesCtrl.dispose();
    _grantCtrl.dispose();
    _testEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    setState(() => _loadingCounts = true);
    final prov = context.read<AppProvider>();
    final reg = await prov.registeredUserCount();
    final act = await prov.activeUserCount();
    final paid = await prov.paidUserCount();
    if (!mounted) return;
    setState(() {
      _registered = reg;
      _active = act;
      _paid = paid;
      _loadingCounts = false;
    });
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.red : _accent,
        content: Text(msg,
            style: GoogleFonts.inder(color: Colors.white, fontSize: 13)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (context, prov, _) {
      final t = prov.appTheme;

      // Defence in depth — never render the panel for a non-admin.
      if (!prov.isAdmin) return _accessDenied(t);

      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Column(children: [
            _topBar(t),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _accessBanner(prov, t),
                      const SizedBox(height: 16),
                      _metricsCard(prov, t),
                      const SizedBox(height: 16),
                      _testNotificationCard(prov, t),
                      const SizedBox(height: 16),
                      _timerCard(prov, t),
                      const SizedBox(height: 16),
                      _statsCard(prov, t),
                      const SizedBox(height: 16),
                      _privilegesCard(t),
                      const SizedBox(height: 16),
                      if (prov.isRootAdmin) _manageAdminsCard(prov, t),
                    ]),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── Access denied ───────────────────────────────────────────────────────────
  Widget _accessDenied(AppThemeData t) => Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, color: AppColors.red, size: 54),
                const SizedBox(height: 16),
                Text('Access denied',
                    style: GoogleFonts.inder(
                        color: t.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('This area is for administrators only.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 14)),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('Go back',
                        style: GoogleFonts.inder(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _topBar(AppThemeData t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(Icons.chevron_left_rounded,
                  color: t.textPrimary, size: 28),
            ),
          ),
          const Icon(Icons.shield_rounded, color: _accent, size: 22),
          const SizedBox(width: 8),
          Text('Admin Panel',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  // ── Access banner ─────────────────────────────────────────────────────────
  Widget _accessBanner(AppProvider prov, AppThemeData t) {
    final root = prov.isRootAdmin;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _accent.withOpacity(t.isDark ? 0.25 : 0.14),
          _accent.withOpacity(0.0),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: _accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.verified_user_rounded,
              color: _accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prov.currentEmail ?? 'Signed in',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(root ? 'ROOT ADMIN' : 'ADMIN',
                  style: GoogleFonts.inder(
                      color: _accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Card scaffold ───────────────────────────────────────────────────────────
  Widget _card(AppThemeData t, IconData icon, String title, List<Widget> children,
      {Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.widgetBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.widgetShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  // ── Metrics ─────────────────────────────────────────────────────────────────
  Widget _metricsCard(AppProvider prov, AppThemeData t) {
    return _card(
      t,
      Icons.insights_rounded,
      'App Usage',
      [
        Row(children: [
          Expanded(
              child: _metricTile(t, 'Registered',
                  _loadingCounts ? '…' : '${_registered ?? 0}',
                  Icons.people_alt_rounded)),
          const SizedBox(width: 10),
          Expanded(
              child: _metricTile(t, 'Active now',
                  _loadingCounts ? '…' : '${_active ?? 0}',
                  Icons.bolt_rounded)),
          const SizedBox(width: 10),
          Expanded(
              child: _metricTile(t, 'Paid users',
                  _loadingCounts ? '…' : '${_paid ?? 0}',
                  Icons.workspace_premium_rounded)),
        ]),
        const SizedBox(height: 8),
        Text(
            '"Active now" = accounts seen in the last 10 minutes. '
            '"Paid users" updates once a paywall is live.',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
        // Clean up Firestore docs left by accounts deleted from Auth, so the
        // Registered count reflects reality. Root admins only.
        if (prov.isRootAdmin) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _purging ? null : () => _runPurge(prov),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.red.withOpacity(0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_purging)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.red))
                else
                  const Icon(Icons.cleaning_services_rounded,
                      color: AppColors.red, size: 16),
                const SizedBox(width: 8),
                Text(_purging ? 'Cleaning…' : 'Clean up deleted accounts',
                    style: GoogleFonts.inder(
                        color: AppColors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ],
      trailing: GestureDetector(
        onTap: _loadingCounts ? null : _loadCounts,
        child: Icon(Icons.refresh_rounded,
            color: _loadingCounts ? t.textMuted : _accent, size: 20),
      ),
    );
  }

  Future<void> _runPurge(AppProvider prov) async {
    setState(() => _purging = true);
    final res = await prov.purgeDeletedUsers();
    if (!mounted) return;
    setState(() => _purging = false);
    if (res == null) {
      _toast('Cleanup unavailable — deploy the push server and set PUSH_ENDPOINT',
          error: true);
      return;
    }
    _toast('Removed ${res['purged']} deleted account(s)');
    _loadCounts();
  }

  Widget _metricTile(AppThemeData t, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
          color: t.inputBg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(height: 8),
        Text(value,
            style: GoogleFonts.inder(
                color: t.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
      ]),
    );
  }

  // ── Test notification ─────────────────────────────────────────────────────────
  Widget _testNotificationCard(AppProvider prov, AppThemeData t) {
    return _card(t, Icons.notifications_active_rounded, 'Test Notification', [
      Text(
          'Send a test "study reminder" to an account by email to check the '
          'notification pipeline (push shows on their phone once the Cloud '
          'Function is deployed; otherwise it appears in their in-app panel).',
          style: GoogleFonts.inder(color: t.textMuted, fontSize: 12, height: 1.4)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _testEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'user@email.com',
              hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 13),
              filled: true,
              fillColor: t.inputBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _btn('Send', _accent, Colors.white, () async {
          final email = _testEmailCtrl.text.trim();
          if (email.isEmpty) return;
          final res = await prov.sendStudyReminderByEmail(email);
          if (!mounted) return;
          switch (res) {
            case 'sent':
              _testEmailCtrl.clear();
              _toast('Notification sent to $email');
              break;
            case 'no_account':
              _toast('No account found for that email', error: true);
              break;
            default:
              _toast('Could not send notification', error: true);
          }
        }, expand: false),
      ]),
    ]);
  }

  // ── Timer config ─────────────────────────────────────────────────────────────
  static const Map<int, String> _timeOptions = {
    10: '10 sec',
    30: '30 sec',
    60: '1 min',
    120: '2 min',
    300: '5 min',
    600: '10 min',
    900: '15 min',
    1200: '20 min',
    1500: '25 min',
    1800: '30 min',
    2700: '45 min',
    3600: '60 min',
  };

  Widget _timeDropdown(
      AppThemeData t, String label, int value, ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14)),
        ),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: t.inputBg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: DropdownButton<int>(
            value: _timeOptions.containsKey(value) ? value : _timeOptions.keys.first,
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down, color: t.textMuted, size: 18),
            dropdownColor: t.surface,
            style: GoogleFonts.inder(
                color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
            onChanged: onChanged,
            items: _timeOptions.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }

  Widget _timerCard(AppProvider prov, AppThemeData t) {
    return _card(t, Icons.timer_rounded, 'Pomodoro Timings', [
      _timeDropdown(t, 'Focus', _focus, (v) => setState(() => _focus = v!)),
      _timeDropdown(t, 'Short break', _short, (v) => setState(() => _short = v!)),
      _timeDropdown(t, 'Long break', _long, (v) => setState(() => _long = v!)),
      _stepper(t, 'Cycles', _cycles, '', (v) => setState(() => _cycles = v),
          min: 1, max: 12),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: _btn('Save', _accent, Colors.white, () async {
            await prov.setTimerConfig(
                focusSecs: _focus,
                shortBreakSecs: _short,
                longBreakSecs: _long,
                cycles: _cycles);
            _toast('Timer settings saved');
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _btn('Reset', t.inputBg, t.textPrimary, () async {
            await prov.resetTimerConfig();
            setState(() {
              _focus = prov.focusSecs;
              _short = prov.shortBreakSecs;
              _long = prov.longBreakSecs;
              _cycles = prov.cyclesPerSession;
            });
            _toast('Reset to default (25 / 5 / 15 × 4)');
          }),
        ),
      ]),
      const SizedBox(height: 8),
      Text('Applies to your timer only — other users keep the defaults.',
          style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
    ]);
  }

  Widget _stepper(AppThemeData t, String label, int value, String unit,
      ValueChanged<int> onChanged,
      {required int min, required int max}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14)),
        ),
        _roundBtn(t, Icons.remove_rounded,
            value > min ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 64,
          child: Text(unit.isEmpty ? '$value' : '$value $unit',
              textAlign: TextAlign.center,
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ),
        _roundBtn(t, Icons.add_rounded,
            value < max ? () => onChanged(value + 1) : null),
      ]),
    );
  }

  Widget _roundBtn(AppThemeData t, IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? _accent.withOpacity(0.15) : t.inputBg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon,
            color: enabled ? _accent : t.textMuted, size: 18),
      ),
    );
  }

  // ── Stat overrides ───────────────────────────────────────────────────────────
  Widget _statsCard(AppProvider prov, AppThemeData t) {
    return _card(
      t,
      Icons.tune_rounded,
      'My Stats',
      [
        _numField(t, 'Current streak (days)', _streakCtrl),
        const SizedBox(height: 10),
        _numField(t, 'Best streak (days)', _bestCtrl),
        const SizedBox(height: 10),
        _numField(t, 'Sessions completed', _sessionsCtrl),
        const SizedBox(height: 10),
        _numField(t, 'Total study time (minutes)', _minutesCtrl),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _btn('Apply', _accent, Colors.white, () async {
              await prov.adminSetStatOverrides(
                streak: int.tryParse(_streakCtrl.text.trim()),
                bestStreak: int.tryParse(_bestCtrl.text.trim()),
                sessions: int.tryParse(_sessionsCtrl.text.trim()),
                studyMinutes: int.tryParse(_minutesCtrl.text.trim()),
              );
              _toast('Stats updated');
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _btn('Reset to real', t.inputBg, t.textPrimary, () async {
              await prov.clearStatOverrides();
              _fillStatFields(prov);
              _toast('Showing real stats again');
            }),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
            prov.hasStatOverrides
                ? '● Overrides are active. These values are shown across your profile and groups.'
                : 'Set custom values, or leave a field empty to keep it derived.',
            style: GoogleFonts.inder(
                color: prov.hasStatOverrides ? _accent : t.textMuted,
                fontSize: 11)),
      ],
    );
  }

  Widget _numField(AppThemeData t, String label, TextEditingController c) {
    return Row(children: [
      Expanded(
        child: Text(label,
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 92,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: GoogleFonts.inder(
              color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.inputBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
      ),
    ]);
  }

  // ── Privileges (info) ────────────────────────────────────────────────────────
  Widget _privilegesCard(AppThemeData t) {
    return _card(t, Icons.workspace_premium_rounded, 'Admin Privileges', [
      _privRow(t, Icons.groups_rounded, 'Unlimited groups',
          'The 5-group limit is lifted for you.'),
      _privRow(t, Icons.auto_awesome_rounded, 'AI features unlocked',
          'Unlimited access to AI quizzes and answer sheet scans (no quotas).'),
      _privRow(t, Icons.timer_rounded, 'Custom Pomodoro timings',
          'Set above — your timer only.'),
    ]);
  }

  Widget _privRow(AppThemeData t, IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.check_rounded,
              color: AppColors.green, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inder(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text(sub,
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  // ── Manage admins (root only) ─────────────────────────────────────────────────
  Widget _manageAdminsCard(AppProvider prov, AppThemeData t) {
    return _card(t, Icons.admin_panel_settings_rounded, 'Manage Admins', [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _grantCtrl,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Grant admin by email',
              hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 13),
              filled: true,
              fillColor: t.inputBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _btn('Grant', _accent, Colors.white, () async {
          final email = _grantCtrl.text.trim();
          if (email.isEmpty) return;
          final res = await prov.grantAdminByEmail(email);
          if (!mounted) return;
          switch (res) {
            case 'granted':
              _grantCtrl.clear();
              _toast('Admin granted to $email');
              break;
            case 'no_account':
              _toast('No account found for that email', error: true);
              break;
            default:
              _toast('Could not grant admin (check rules)', error: true);
          }
        }, expand: false),
      ]),
      const SizedBox(height: 14),
      Text('Granted admins',
          style: GoogleFonts.inder(
              color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: prov.adminsStream(),
        builder: (_, snap) {
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return Text('No granted admins yet.',
                style: GoogleFonts.inder(color: t.textMuted, fontSize: 12));
          }
          return Column(
            children: list.map((a) {
              final uid = a['uid'] as String? ?? '';
              final email = (a['email'] as String?) ?? uid;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: t.inputBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.person_rounded, color: _accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inder(
                            color: t.textPrimary, fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await prov.revokeAdmin(uid);
                      _toast('Admin revoked');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.person_remove_rounded,
                          color: AppColors.red, size: 16),
                    ),
                  ),
                ]),
              );
            }).toList(),
          );
        },
      ),
      const SizedBox(height: 6),
      Text('Root admins are set in code (admin_config.dart) and can\'t be revoked here.',
          style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
    ]);
  }

  // ── Shared button ─────────────────────────────────────────────────────────────
  Widget _btn(String label, Color bg, Color fg, VoidCallback onTap,
      {bool expand = true}) {
    final child = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding:
            EdgeInsets.symmetric(vertical: 12, horizontal: expand ? 0 : 18),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        child: Text(label,
            style: GoogleFonts.inder(
                color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
    return child;
  }
}
