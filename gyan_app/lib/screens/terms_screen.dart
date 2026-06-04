import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _isDark = false; // starts in white mode

  static const _blue = Color(0xFF5865F2);
  static const _green = Color(0xFF57F287);

  Color get bg =>
      _isDark ? const Color(0xFF121318) : const Color(0xFFF8F9FC);

  Color get card =>
      _isDark ? const Color(0xFF18181F) : Colors.white;

  Color get text =>
      _isDark ? Colors.white : const Color(0xFF1A1A22);

  Color get muted =>
      _isDark ? const Color(0xFF6E6E78) : const Color(0xFF666670);

  Color get divider =>
      _isDark
          ? const Color(0xFF2A2A35)
          : Colors.black.withOpacity(.08);

  Color get border =>
      _isDark
          ? Colors.white.withOpacity(.06)
          : Colors.black.withOpacity(.06);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,

      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,

        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: text,
          ),
          onPressed: () => Navigator.pop(context),
        ),

        title: Text(
          'Terms & Conditions',
          style: GoogleFonts.inder(
            color: text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),

        actions: [
          Row(
            children: [
              Icon(
                _isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                color: text,
                size: 20,
              ),
              Switch(
                value: _isDark,
                activeColor: _blue,
                onChanged: (v) {
                  setState(() {
                    _isDark = v;
                  });
                },
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: divider,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // HEADER

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _blue.withOpacity(.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _blue.withOpacity(.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [
                      const Icon(
                        Icons.auto_stories_rounded,
                        color: _blue,
                        size: 22,
                      ),

                      const SizedBox(width: 10),

                      Text(
                        'GYAN',
                        style: GoogleFonts.inder(
                          color: _blue,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Terms of Service & Privacy Policy',
                    style: GoogleFonts.inder(
                      color: text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Last updated: June 2026 · Effective immediately upon registration',
                    style: GoogleFonts.inder(
                      color: muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            _buildIntro(),

            _buildSection(
              number: '1',
              title: 'Acceptance of Terms',
              content:
                  'By creating an account on GYAN, you confirm that you have read, understood, and agree to be bound by these Terms of Service.',
            ),

            _buildSection(
              number: '2',
              title: 'User Accounts',
              content:
                  'You are responsible for maintaining account confidentiality and activity under your account.',
            ),

            _buildSection(
              number: '3',
              title: 'Data We Collect',
              content:
                  'GYAN may collect email addresses, study data, preferences and device information.',
            ),

            _buildSection(
              number: '4',
              title: 'How We Use Your Data',
              content:
                  'We use data to provide services, sync progress and improve the experience.',
            ),

            _buildSection(
              number: '5',
              title: 'AI Powered Features',
              content:
                  'GYAN uses third-party AI services for educational features.',
            ),

            const SizedBox(height: 24),

            // FOOTER

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _green.withOpacity(.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _green.withOpacity(.2),
                ),
              ),
              child: Column(
                children: [

                  const Icon(
                    Icons.verified_rounded,
                    color: _green,
                    size: 28,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'By registering, you agree to all terms.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inder(
                      color: text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'GYAN is built by students, for students.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inder(
                      color: muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),

                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),

                child: Text(
                  'I Understand',
                  style: GoogleFonts.inder(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        'Welcome to GYAN! These Terms of Service govern your use of our study productivity application.',
        style: GoogleFonts.inder(
          color: muted,
          fontSize: 13,
          height: 1.7,
        ),
      ),
    );
  }

  Widget _buildSection({
    required String number,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,

                decoration: BoxDecoration(
                  color: _blue.withOpacity(.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _blue.withOpacity(.3),
                  ),
                ),

                child: Text(
                  number,
                  style: GoogleFonts.inder(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inder(
                    color: text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),

            child: Text(
              content,
              style: GoogleFonts.inder(
                color: text.withOpacity(.75),
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),

          const SizedBox(height: 4),

          Container(
            height: 1,
            color: divider,
          ),
        ],
      ),
    );
  }
}