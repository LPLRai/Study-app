import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class WhiteNoiseWidget extends StatefulWidget {
  const WhiteNoiseWidget({super.key});
  @override
  State<WhiteNoiseWidget> createState() => _WhiteNoiseWidgetState();
}

class _WhiteNoiseWidgetState extends State<WhiteNoiseWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isExpanded = false;
  int _selectedIdx = 0;
  double _volume = 0.5;

  static const List<Map<String, dynamic>> _sounds = [
    {'name': 'Rain',   'icon': Icons.water_drop_rounded,            'asset': 'audio/rain.mp3'},
    {'name': 'Forest', 'icon': Icons.forest_rounded,                'asset': 'audio/forest.mp3'},
    {'name': 'Cafe',   'icon': Icons.local_cafe_rounded,            'asset': 'audio/cafe.mp3'},
    {'name': 'Ocean',  'icon': Icons.waves_rounded,                 'asset': 'audio/ocean.mp3'},
    {'name': 'Fire',   'icon': Icons.local_fire_department_rounded, 'asset': 'audio/fire.mp3'},
  ];

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.loop);
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.getVolume().then((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    VolumeController.instance.addListener((vol) {
      if (mounted) setState(() => _volume = vol);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    VolumeController.instance.removeListener();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _player.play(AssetSource(_sounds[_selectedIdx]['asset']!));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _switchSound(int idx) async {
    setState(() => _selectedIdx = idx);
    if (_isPlaying) {
      await _player.stop();
      await _player.play(AssetSource(_sounds[idx]['asset']!));
    }
  }

  void _onVolumeChanged(double v) {
    setState(() => _volume = v);
    VolumeController.instance.setVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppProvider>().appTheme;

    return TapRegion(
      onTapOutside: (event) {
        if (_isExpanded) setState(() => _isExpanded = false);
      },
      child: GestureDetector(
        // Collapsed: tapping anywhere on the card opens it.
        // Expanded: this no-ops, so tapping the body does NOT close the card.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_isExpanded) setState(() => _isExpanded = true);
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.widgetBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.cardBorder),
          boxShadow: [
            BoxShadow(
              color: t.isDark ? Colors.black38 : Colors.black12,
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ── tap to close, but ONLY while expanded ──────────
          // When collapsed, this claims no taps (onTap == null) so they fall
          // through to the card-level opener above — making the whole card
          // clickable to open. When expanded, only this header closes it.
          GestureDetector(
            behavior: _isExpanded
                ? HitTestBehavior.opaque
                : HitTestBehavior.deferToChild,
            onTap: _isExpanded
                ? () => setState(() => _isExpanded = false)
                : null,
            child: Row(children: [
              Icon(Icons.headphones_rounded, color: t.textPrimary, size: 22),
              const SizedBox(width: 10),
              Text(
                'White Noise',
                style: GoogleFonts.inder(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Collapsed: subtle "now playing" pulse only. No open arrow —
              // tapping anywhere on the card opens it.
              if (!_isExpanded && _isPlaying)
                Icon(Icons.graphic_eq_rounded, color: AppColors.blue, size: 22),
            ]),
          ),

          // ── Expanded body ────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _isExpanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 14),
                      Divider(color: t.cardBorder, height: 1),
                      const SizedBox(height: 20),

                      // Evenly-spaced, centered row of sound options
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          _sounds.length,
                          (i) => _buildSoundIcon(t, i),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Big play / pause button — centered
                      Center(child: _buildPlayButton(t)),

                      const SizedBox(height: 22),

                      // ── Volume slider ──────────────────────────────
                      Row(children: [
                        Icon(Icons.volume_down_rounded,
                            color: t.textMuted, size: 22),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 10),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 20),
                              activeTrackColor: AppColors.blue,
                              inactiveTrackColor:
                                  t.isDark ? Colors.white24 : Colors.black12,
                              thumbColor: AppColors.blue,
                            ),
                            child: Slider(
                              value: _volume,
                              min: 0,
                              max: 1,
                              onChanged: _onVolumeChanged,
                            ),
                          ),
                        ),
                        Icon(Icons.volume_up_rounded,
                            color: t.textMuted, size: 22),
                      ]),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
      ),
    );
  }

  // Large play/pause control — bare triangle (no circle).
  Widget _buildPlayButton(AppThemeData t) {
    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: _isPlaying ? AppColors.blue : t.textPrimary,
          size: 64,
        ),
      ),
    );
  }

  // A single selectable sound option (icon circle + label).
  Widget _buildSoundIcon(AppThemeData t, int i) {
    final selected = _selectedIdx == i;
    final IconData iconData = _sounds[i]['icon'] as IconData;
    return GestureDetector(
      onTap: () => _switchSound(i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.blue.withOpacity(0.15) : t.inputBg,
              border: selected
                  ? Border.all(color: AppColors.blue, width: 2)
                  : Border.all(color: t.cardBorder),
            ),
            child: Icon(
              iconData,
              size: 28,
              color: selected ? AppColors.blue : t.textMuted,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _sounds[i]['name']!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inder(
              color: selected ? AppColors.blue : t.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
