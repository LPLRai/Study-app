// ─────────────────────────────────────────────────────────────────────────────
// widgets/white_noise_widget.dart
//
// Floating white-noise player — theme-aware.
//
// SETUP:
//  1. pubspec.yaml: audioplayers: ^6.0.0
//  2. Download royalty-free MP3s → assets/audio/
//     rain.mp3 / forest.mp3 / cafe.mp3 / ocean.mp3 / fire.mp3
//     Recommended: https://pixabay.com/sound-effects/
//  3. Uncomment assets block in pubspec.yaml:
//       assets:
//         - assets/audio/
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/app_provider.dart';

class WhiteNoiseWidget extends StatefulWidget {
  const WhiteNoiseWidget({super.key});
  @override State<WhiteNoiseWidget> createState() => _WhiteNoiseWidgetState();
}

class _WhiteNoiseWidgetState extends State<WhiteNoiseWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool   _isPlaying   = false;
  bool   _isExpanded  = false;
  int    _selectedIdx = 0;
  double _volume      = 0.5;

  // put (audio file) paths in the 'asset' field below
  static const List<Map<String, String>> _sounds = [
    {'name': 'Rain',   'emoji': '🌧️', 'asset': 'audio/rain.mp3'},    // put rain audio path in this section
    {'name': 'Forest', 'emoji': '🌲', 'asset': 'audio/forest.mp3'},  // put forest audio path in this section
    {'name': 'Cafe',   'emoji': '☕', 'asset': 'audio/cafe.mp3'},     // put cafe audio path in this section
    {'name': 'Ocean',  'emoji': '🌊', 'asset': 'audio/ocean.mp3'},    // put ocean audio path in this section
    {'name': 'Fire',   'emoji': '🔥', 'asset': 'audio/fire.mp3'},     // put fire audio path in this section
  ];

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.loop);
    _player.setVolume(_volume);
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

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

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppProvider>().appTheme;

    return Container(
      margin:  const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        t.widgetBg,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: t.cardBorder),
        boxShadow: [
          BoxShadow(
            color:      t.isDark ? Colors.black38 : Colors.black12,
            blurRadius: 12,
            offset:     const Offset(0, -2),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Header row ──────────────────────────────────────────────
        Row(children: [
          Icon(Icons.headphones_rounded, color: t.textMuted, size: 18),
          const SizedBox(width: 8),
          Text('White Noise', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Icon(_isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: t.textMuted, size: 20),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _togglePlay,
            child: Icon(
              _isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_outline_rounded,
              color: t.textPrimary, size: 26,
            ),
          ),
        ]),

        // ── Expanded panel ───────────────────────────────────────────
        if (_isExpanded) ...[
          const SizedBox(height: 14),
          // Sound options
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_sounds.length, (i) {
                final selected = _selectedIdx == i;
                return GestureDetector(
                  onTap: () => _switchSound(i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 18),
                    child: Column(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          shape:  BoxShape.circle,
                          color:  selected ? AppColors.blue.withOpacity(0.2) : t.inputBg,
                          border: selected
                              ? Border.all(color: AppColors.blue, width: 2)
                              : Border.all(color: t.cardBorder),
                        ),
                        child: Center(child: Text(_sounds[i]['emoji']!, style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(height: 5),
                      Text(_sounds[i]['name']!,
                          style: GoogleFonts.inder(
                              color:    selected ? AppColors.blue : t.textMuted,
                              fontSize: 11)),
                    ]),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // Volume slider
          Row(children: [
            Icon(Icons.volume_mute, color: t.textMuted, size: 16),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight:        2,
                  thumbShape:         const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:       const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor:   AppColors.blue,
                  inactiveTrackColor: t.isDark ? Colors.white24 : Colors.black12,
                  thumbColor:         AppColors.blue,
                ),
                child: Slider(
                  value: _volume, min: 0, max: 1,
                  onChanged: (v) async {
                    setState(() => _volume = v);
                    await _player.setVolume(v);
                  },
                ),
              ),
            ),
            Icon(Icons.volume_up, color: t.textMuted, size: 16),
          ]),
        ],
      ]),
    );
  }
}
