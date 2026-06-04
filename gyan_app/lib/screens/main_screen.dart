import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/profile_avatar.dart';
import 'home_screen.dart';
import 'timer_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'ai_features_screen.dart';


class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const List<Widget> _pages = [
    HomeScreen(), TimerScreen(), AiFeaturesScreen(), GroupsScreen(), ProfileScreen(),
  ];

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;

  // Vibrant violet accent used for the selected nav pill (matches the design).
  static const _accent = Color(0xFF7C5CFF);

  // Tab definitions — order matters and maps 1:1 to [_pages].
  static const List<_NavTab> _tabs = [
    _NavTab(icon: Icons.home_rounded,        label: 'Home'),
    _NavTab(icon: Icons.trending_up_rounded, label: 'Timer'),
    _NavTab(icon: Icons.auto_awesome_rounded, label: 'AI Features'),
    _NavTab(icon: Icons.menu_book_rounded,   label: 'Groups'),
    _NavTab(icon: Icons.person_rounded,      label: 'Profile', isAvatar: true),
  ];

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
      bottomNavigationBar: _buildNavBar(prov, t, tabIndex),
    );
  }

  Widget _buildNavBar(AppProvider prov, t, int tabIndex) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The bar tracks the screen width (full width minus side margins),
          // but is capped on very wide screens so it never looks sparse.
          const sideMargin = 16.0;
          final available = constraints.maxWidth - sideMargin * 2;
          final barWidth = available > 520 ? 520.0 : available;

          // Row (not Center/Align) so the bar wraps its own height instead of
          // expanding to fill the loose constraints the bottom-nav slot gives.
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: barWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.navBar,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: t.cardBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(t.isDark ? 0.35 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  // spaceBetween spreads the tabs across the full bar width, so
                  // the gaps grow and shrink with the screen.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 0; i < _tabs.length; i++)
                        _buildItem(prov, t, i, i == tabIndex),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildItem(AppProvider prov, t, int index, bool selected) {
    final tab = _tabs[index];
    final Color iconColor = selected ? Colors.white : t.textMuted;

    final Widget leading = tab.isAvatar
        ? _avatar(prov, t, selected)
        : Icon(tab.icon, size: 22, color: iconColor);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTabTapped(index, prov),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10),
        decoration: BoxDecoration(
          color: selected
              ? _accent
              : (t.isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            // Label is only revealed for the selected tab.
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: GoogleFonts.inder(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(AppProvider prov, t, bool selected) {
    final imgPath = prov.user.profileImagePath;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.isDark ? Colors.white12 : Colors.black12,
        border: selected
            ? Border.all(color: Colors.white, width: 1.5)
            : null,
      ),
      child: ClipOval(
        child: profileImageChild(imgPath,
            icon: Icons.person_rounded,
            color: selected ? Colors.white : t.textMuted,
            iconSize: 16),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final String label;
  final bool isAvatar;

  const _NavTab({
    required this.icon,
    required this.label,
    this.isAvatar = false,
  });
}
