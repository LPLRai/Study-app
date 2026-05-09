import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/group_model.dart';
import '../providers/app_provider.dart';

enum _Range { today, week, month }

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  _Range _range = _Range.today;

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_range) {
      case _Range.today: return DateTime(now.year, now.month, now.day);
      case _Range.week:  return now.subtract(const Duration(days: 6));
      case _Range.month: return now.subtract(const Duration(days: 29));
    }
  }

  Map<String, _Entry> _buildChartData(AppProvider prov) {
    final end     = DateTime.now().add(const Duration(minutes: 1));
    final timeMap = prov.studyTimePerSubject(_rangeStart, end);
    final result  = <String, _Entry>{};
    for (final s in prov.sessions) {
      if (!timeMap.containsKey(s.subjectId)) continue;
      if (result.containsKey(s.subjectId)) continue;
      result[s.subjectId] = _Entry(s.subjectName, s.colorIndex, timeMap[s.subjectId]!);
    }
    return result;
  }

  void _showGroupOverlay(BuildContext ctx, AppProvider prov) {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    String? expandedId;
    final t = prov.appTheme;

    showModalBottomSheet(
      context: ctx, backgroundColor: t.background, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, ss) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Add / Remove Groups', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                IconButton(icon: Icon(Icons.close, color: t.textPrimary), onPressed: () => Navigator.pop(ctx2)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(
                  controller: nameCtrl, style: GoogleFonts.inder(color: t.textPrimary),
                  decoration: InputDecoration(hintText: 'Group name', hintStyle: GoogleFonts.inder(color: t.textMuted),
                      filled: true, fillColor: t.inputBg, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                )),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () { if (nameCtrl.text.trim().isNotEmpty) { prov.addGroup(nameCtrl.text.trim()); nameCtrl.clear(); ss(() {}); } },
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(8)),
                      child: Text('Add', style: GoogleFonts.inder(color: Colors.white, fontSize: 14))),
                ),
              ]),
              const SizedBox(height: 18),
              if (prov.groups.isNotEmpty) ...[
                Text('Your groups:', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                ...prov.groups.map((g) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(Icons.group_rounded, color: t.textMuted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(g.name, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 14))),
                      GestureDetector(onTap: () => ss(() => expandedId = expandedId == g.id ? null : g.id),
                          child: const Icon(Icons.person_add_outlined, color: AppColors.blue, size: 20)),
                      const SizedBox(width: 12),
                      GestureDetector(onTap: () { prov.removeGroup(g.id); ss(() { if (expandedId == g.id) expandedId = null; }); },
                          child: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.red, size: 20)),
                    ]),
                  ),
                  if (expandedId == g.id)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(color: t.inputBg, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Expanded(child: TextField(
                          controller: emailCtrl, keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13),
                          decoration: InputDecoration(hintText: 'member@email.com', hintStyle: GoogleFonts.inder(color: t.textMuted, fontSize: 13), isDense: true, border: InputBorder.none),
                        )),
                        GestureDetector(
                          onTap: () { if (emailCtrl.text.trim().isNotEmpty) { prov.addMemberToGroup(g.id, emailCtrl.text.trim()); emailCtrl.clear(); ss(() {}); } },
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(6)),
                              child: Text('Invite', style: GoogleFonts.inder(color: Colors.white, fontSize: 12))),
                        ),
                      ]),
                    ),
                ])),
              ],
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(builder: (ctx, prov, _) {
      final t         = prov.appTheme;
      final chartData = _buildChartData(prov);
      return SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Stack(alignment: Alignment.center, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => prov.switchTab(0),
                  child: Icon(Icons.chevron_left_rounded, color: t.textPrimary, size: 28),
                ),
              ),
              Text('Groups', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _chartCard(chartData, t),
                const SizedBox(height: 20),
                if (prov.groups.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('No groups yet — press Edit to create one', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13))),
                  )
                else
                  ...prov.groups.map((g) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _groupTile(g, t))),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _showGroupOverlay(ctx, prov),
                  child: Row(children: [
                    Icon(Icons.edit, color: t.textMuted, size: 15),
                    const SizedBox(width: 5),
                    Text('Edit', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _chartCard(Map<String, _Entry> data, t) {
    final maxMins = data.values.isEmpty ? 1 : data.values.map((e) => e.minutes).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total time studied', style: GoogleFonts.inder(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          _dropdown(t),
        ]),
        const SizedBox(height: 18),
        if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('No study data for this period', style: GoogleFonts.inder(color: t.textMuted, fontSize: 13))),
          )
        else
          ...data.values.map((e) => _bar(e, maxMins, t)),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            _range == _Range.today ? 'Minutes today' : _range == _Range.week ? 'Minutes this week' : 'Minutes this month',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 11),
          ),
        ),
      ]),
    );
  }

  Widget _bar(_Entry e, int maxMins, t) {
    final color    = AppColors.subjectColor(e.colorIndex);
    final fraction = maxMins > 0 ? e.minutes / maxMins : 0.0;
    final label    = '${e.minutes ~/ 60}h ${e.minutes % 60}m';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(e.subjectName, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13)),
          ]),
          Text(label, style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (_, c) => Stack(children: [
          Container(height: 10, width: c.maxWidth, decoration: BoxDecoration(color: t.overlayLight, borderRadius: BorderRadius.circular(6))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500), curve: Curves.easeOut,
            height: 10, width: c.maxWidth * fraction.clamp(0.0, 1.0),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          ),
        ])),
      ]),
    );
  }

  Widget _dropdown(t) => DropdownButtonHideUnderline(
    child: DropdownButton<_Range>(
      value: _range,
      dropdownColor: t.widgetBg,
      icon: Icon(Icons.arrow_drop_down, color: t.textMuted, size: 18),
      style: GoogleFonts.inder(color: t.textPrimary, fontSize: 13),
      onChanged: (v) { if (v != null) setState(() => _range = v); },
      items: const [
        DropdownMenuItem(value: _Range.today, child: Text('Today')),
        DropdownMenuItem(value: _Range.week,  child: Text('Week')),
        DropdownMenuItem(value: _Range.month, child: Text('Month')),
      ],
    ),
  );

  Widget _groupTile(GroupModel g, t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(color: t.widgetBg, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(g.name, style: GoogleFonts.inder(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        Text(g.memberCount == 0 ? 'No members yet' : 'There are ${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
            style: GoogleFonts.inder(color: t.textMuted, fontSize: 12)),
      ])),
      // put (group_icon) path in this section
      Icon(Icons.groups_rounded, color: t.textMuted, size: 36),
    ]),
  );
}

class _Entry {
  final String subjectName;
  final int    colorIndex;
  final int    minutes;
  const _Entry(this.subjectName, this.colorIndex, this.minutes);
}
