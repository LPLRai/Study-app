import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import 'sign_out_dialog.dart';
class ProfileModal extends StatelessWidget {
  const ProfileModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t = prov.appTheme;
      final user = prov.user;
      final imgPath = user.profileImagePath;
      final totalMin = prov.totalMinutesAllTime; // session-derived, accurate
      final totalHrs = totalMin / 60;

      return Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.widgetBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.blue.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Profile info ───────────────────────────────────────
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: t.background,
                ),
                child: ClipOval(
                  child: imgPath != null && File(imgPath).existsSync()
                      ? Image.file(File(imgPath), fit: BoxFit.cover)
                      : Icon(Icons.person_rounded, color: t.textMuted, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    user.name,
                    style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    user.grade.isEmpty ? 'Grade: N/A' : 'Grade: ${user.grade}',
                    style: GoogleFonts.inder(color: t.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),

            const SizedBox(height: 14),
            Container(height: 1, color: t.divider),
            const SizedBox(height: 12),

            // ── Stats ──────────────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Studied', style: GoogleFonts.inder(color: t.textMuted, fontSize: 10)),
                Text(
                  totalHrs < 1 ? '${totalMin}m' : '${totalHrs.toStringAsFixed(1)}h',
                  style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sessions', style: GoogleFonts.inder(color: t.textMuted, fontSize: 10)),
                Text(
                  '${prov.totalSessionsCount}',
                  style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Streak', style: GoogleFonts.inder(color: t.textMuted, fontSize: 10)),
                Text(
                  '${prov.bestStreakDays}',
                  style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ]),
            ]),

            const SizedBox(height: 12),
            Container(height: 1, color: t.divider),
            const SizedBox(height: 12),

            // ── Goal ───────────────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Daily Goal', style: GoogleFonts.inder(color: t.textMuted, fontSize: 11)),
              Text(
                '${user.dailyStudyGoalHours}h',
                style: GoogleFonts.inder(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ]),

            const SizedBox(height: 12),
            Container(height: 1, color: t.divider),
            const SizedBox(height: 12),

            // ── Theme toggle ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dark Mode', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Switch(
                  value: prov.isDarkMode,
                  onChanged: (value) => prov.setDarkMode(value),
                  activeColor: Colors.white,
                  activeTrackColor: AppColors.blue,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: t.inputBg,
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Container(height: 1, color: t.divider),
            const SizedBox(height: 12),

            // ── Sign out button ────────────────────────────────────
            GestureDetector(
              onTap: () => confirmSignOut(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withOpacity(0.3)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.logout_rounded, color: AppColors.red, size: 16),
                  const SizedBox(width: 6),
                  Text('Sign Out',
                      style: GoogleFonts.inder(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

