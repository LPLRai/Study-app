// ─────────────────────────────────────────────────────────────────────────────
// widgets/sign_out_dialog.dart
//
// A single, reusable sign-out flow used everywhere the user can sign out.
// Shows a themed confirmation pop-up; on confirm it signs out and returns the
// user to the login screen, clearing the whole navigation stack so they can't
// go "back" into the authenticated app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../screens/auth_screen.dart';

/// Confirms, then signs out and routes to the login screen.
Future<void> confirmSignOut(BuildContext context) async {
  final prov = context.read<AppProvider>();
  // Capture the root navigator before any await so we don't depend on a
  // context that may be disposed (e.g. a closing popup) afterwards.
  final navigator = Navigator.of(context, rootNavigator: true);

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (_) => const _SignOutDialog(),
  );
  if (confirmed != true) return;

  await prov.signOutUser();

  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthScreen()),
    (route) => false,
  );
}

class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog();

  @override
  Widget build(BuildContext context) {
    final t = context.read<AppProvider>().appTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: t.widgetBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.logout_rounded,
                color: AppColors.red, size: 30),
          ),
          const SizedBox(height: 18),
          Text('Sign Out',
              style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('Are you sure you want to sign out of your account?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inder(
                  color: t.textMuted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: _DialogButton(
                label: 'Cancel',
                bg: t.inputBg,
                fg: t.textPrimary,
                border: t.cardBorder,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DialogButton(
                label: 'Sign Out',
                bg: AppColors.red,
                fg: Colors.white,
                border: AppColors.red,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Text(label,
            style: GoogleFonts.inder(
                color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
