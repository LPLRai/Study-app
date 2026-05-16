import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'home_screen.dart';
import 'timer_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'quiz_screen.dart';


class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  static const List<Widget> _pages = [
    HomeScreen(), TimerScreen(), GroupsScreen(), QuizScreen(), ProfileScreen(), 
  ];

  @override
  Widget build(BuildContext context) {
    final prov     = context.watch<AppProvider>();
    final t        = prov.appTheme;
    final tabIndex = prov.currentTabIndex;

    return Scaffold(
      backgroundColor: t.background,
      body: IndexedStack(index: tabIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color:  t.navBar,
          border: Border(top: BorderSide(color: t.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex:        tabIndex,
          onTap:               (i) => prov.switchTab(i),
          backgroundColor:     t.navBar,
          selectedItemColor:   const Color(0xFF5865F2),
          unselectedItemColor: t.textMuted,
          type:                BottomNavigationBarType.fixed,
          elevation:           0,
          selectedLabelStyle:   GoogleFonts.inder(fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inder(fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded),   label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.timer_rounded),   label: 'Timer'),
            BottomNavigationBarItem(icon: Icon(Icons.group_rounded),   label: 'Groups'),
            BottomNavigationBarItem(icon: Icon(Icons.group_rounded),   label: 'Quiz'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded),  label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
