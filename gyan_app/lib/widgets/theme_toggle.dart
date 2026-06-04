import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class ThemeToggle extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const ThemeToggle({
    required this.isDark,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isDark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.blue.withOpacity(0.3), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Icon(Icons.dark_mode_rounded,
                  color: isDark ? Colors.white : AppColors.blue.withOpacity(0.5),
                  size: 16),
              const SizedBox(width: 4),
              Text('Dark',
                  style: GoogleFonts.inder(
                      color: isDark ? Colors.white : AppColors.blue.withOpacity(0.5),
                      fontSize: 11,
                      fontWeight: isDark ? FontWeight.bold : FontWeight.normal)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: !isDark ? AppColors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Icon(Icons.light_mode_rounded,
                  color: !isDark ? Colors.white : AppColors.blue.withOpacity(0.5),
                  size: 16),
              const SizedBox(width: 4),
              Text('Light',
                  style: GoogleFonts.inder(
                      color: !isDark ? Colors.white : AppColors.blue.withOpacity(0.5),
                      fontSize: 11,
                      fontWeight: !isDark ? FontWeight.bold : FontWeight.normal)),
            ]),
          ),
        ]),
      ),
    );
  }
}
