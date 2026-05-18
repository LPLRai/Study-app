import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'home_screen.dart';
import 'timer_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const List<Widget> _pages = [
    HomeScreen(), TimerScreen(), GroupsScreen(), ProfileScreen(),
  ];
  static const int _pageCount = 4;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<AppProvider>().currentTabIndex;
    _pageController = PageController(initialPage: initialTab);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index, AppProvider prov) {
    prov.switchTab(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov     = context.watch<AppProvider>();
    final t        = prov.appTheme;
    final tabIndex = prov.currentTabIndex;

    // Sync PageController with external tab changes (e.g. from Home's "Quick Start")
    if (_pageController.hasClients && _pageController.page?.round() != tabIndex) {
      _pageController.animateToPage(
        tabIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (prov.currentTabIndex != index) {
            prov.switchTab(index);
          }
        },
        physics: const ClampingScrollPhysics(),
        children: MainScreen._pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color:  t.navBar,
          border: Border(top: BorderSide(color: t.divider, width: 1)),
          boxShadow: t.widgetShadow,
        ),
        child: BottomNavigationBar(
          currentIndex:        tabIndex,
          onTap:               (i) => _onTabTapped(i, prov),
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
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded),  label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
