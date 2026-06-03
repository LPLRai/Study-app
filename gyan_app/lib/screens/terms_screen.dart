import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _blue = Color(0xFF5865F2);
  static const _green = Color(0xFF57F287);
  static const _bg = Color(0xFF121318);
  static const _card = Color(0xFF18181F);
  static const _muted = Color(0xFF6E6E78);
  static const _divider = Color(0xFF2A2A35);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terms & Conditions',
          style: GoogleFonts.inder(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header ───────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _blue.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_stories_rounded, color: _blue, size: 22),
                const SizedBox(width: 10),
                Text('GYAN',
                    style: GoogleFonts.inder(
                        color: _blue, fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Text(
                'Terms of Service & Privacy Policy',
                style: GoogleFonts.inder(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Last updated: June 2026 · Effective immediately upon registration',
                style: GoogleFonts.inder(color: _muted, fontSize: 12),
              ),
            ]),
          ),

          const SizedBox(height: 28),

          _buildIntro(),

          _buildSection(
            number: '1',
            title: 'Acceptance of Terms',
            content:
                'By creating an account on GYAN, you confirm that you have read, understood, and agree to be bound by these Terms of Service. If you do not agree with any part of these terms, you may not use our application.\n\nGYAN is a study productivity application designed for students. You must be at least 13 years of age to use this service. If you are under 18, you confirm that you have obtained consent from a parent or guardian.',
          ),

          _buildSection(
            number: '2',
            title: 'User Accounts',
            content:
                'You are responsible for maintaining the confidentiality of your account credentials. You agree to:\n\n• Provide accurate and truthful information during registration\n• Keep your password secure and not share it with others\n• Notify us immediately of any unauthorized use of your account\n• Be responsible for all activity that occurs under your account\n\nGYAN reserves the right to suspend or terminate accounts that violate these terms or engage in fraudulent activity.',
          ),

          _buildSection(
            number: '3',
            title: 'Data We Collect',
            content:
                'GYAN collects the following information to provide our services:\n\n• Email address and username for account creation\n• Study session data (duration, subjects, streaks) to track your progress\n• App preferences such as dark/light mode settings\n• Device information for performance optimization\n\nWe do not sell, rent, or share your personal data with third parties for marketing purposes. Your study data belongs to you.',
          ),

          _buildSection(
            number: '4',
            title: 'How We Use Your Data',
            content:
                'Your data is used exclusively to:\n\n• Provide and improve the GYAN study experience\n• Sync your progress across devices via Firebase (Google)\n• Generate your personal leaderboard ranking and study stats\n• Send account-related emails such as email verification and password reset\n\nAll data is stored securely on Google Firebase servers. We implement industry-standard security measures to protect your information.',
          ),

          _buildSection(
            number: '5',
            title: 'AI-Powered Features',
            content:
                'GYAN uses third-party AI services (Google Gemini and Groq) to power the Quiz Generator feature. When you use this feature:\n\n• Your topic input and notes are sent to the AI provider to generate quiz questions\n• We do not store your quiz inputs or the AI responses permanently\n• AI-generated content is for educational purposes only and may occasionally contain errors\n• You should not rely solely on AI-generated quizzes for academic assessment\n\nBy using the Quiz Generator, you agree to the respective terms of Google Gemini and Groq.',
          ),

          _buildSection(
            number: '6',
            title: 'Acceptable Use',
            content:
                'You agree not to use GYAN to:\n\n• Attempt to gain unauthorized access to other users\' accounts or data\n• Upload harmful, offensive, or illegal content\n• Reverse-engineer, decompile, or attempt to extract source code\n• Use automated scripts or bots to interact with the application\n• Impersonate other users or entities\n\nViolation of these rules may result in immediate account termination.',
          ),

          _buildSection(
            number: '7',
            title: 'Study Groups & Shared Features',
            content:
                'GYAN allows users to create and join study groups. When participating in groups:\n\n• You are responsible for content you share within groups\n• Group members can see your username and study statistics you choose to share\n• Leaderboard rankings are visible to other users within your groups\n• You can leave or delete groups at any time from the Groups section',
          ),

          _buildSection(
            number: '8',
            title: 'Intellectual Property',
            content:
                'The GYAN application, including its design, code, branding, and content, is the intellectual property of the GYAN development team. You may not copy, reproduce, or distribute any part of the application without explicit written permission.\n\nContent you create within GYAN (such as custom subjects and study notes) remains your own intellectual property.',
          ),

          _buildSection(
            number: '9',
            title: 'Disclaimers & Limitation of Liability',
            content:
                'GYAN is provided "as is" without warranties of any kind. We do not guarantee:\n\n• Uninterrupted or error-free operation of the application\n• The accuracy of AI-generated quiz content\n• That your data will never be lost due to technical failure\n\nGYAN shall not be liable for any indirect, incidental, or consequential damages arising from the use or inability to use the application. We strongly recommend regularly backing up important study notes.',
          ),

          _buildSection(
            number: '10',
            title: 'Account Deletion & Data Removal',
            content:
                'You have the right to delete your account at any time. Upon account deletion:\n\n• Your personal data will be removed from our active systems\n• Study session data and progress will be permanently deleted\n• Some anonymized aggregate data may be retained for analytics\n\nTo request account deletion, contact us through the app or email our support team.',
          ),

          _buildSection(
            number: '11',
            title: 'Changes to These Terms',
            content:
                'We may update these Terms of Service from time to time. When we make significant changes, we will notify you via email or an in-app notification. Continued use of GYAN after changes are posted constitutes acceptance of the updated terms.\n\nWe encourage you to review these terms periodically.',
          ),

          _buildSection(
            number: '12',
            title: 'Contact Us',
            content:
                'If you have questions or concerns about these Terms of Service or our privacy practices, please reach out to us:\n\n• Through our gmail @teamgyan457@gmail.com\n• Via our GitHub repository: github.com/LPLRai/Study-app\n\nWe are committed to addressing your concerns promptly and transparently.',
          ),

          const SizedBox(height: 24),

          // ── Footer ───────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _green.withOpacity(0.2)),
            ),
            child: Column(children: [
              const Icon(Icons.verified_rounded, color: _green, size: 28),
              const SizedBox(height: 10),
              Text(
                'By registering, you agree to all of the above terms.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inder(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'GYAN is built by students, for students. We are committed to keeping your data safe and your study experience productive.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inder(color: _muted, fontSize: 12, height: 1.6),
              ),
            ]),
          ),

          const SizedBox(height: 32),

          // ── Close button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('I Understand',
                  style: GoogleFonts.inder(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        'Welcome to GYAN! These Terms of Service govern your use of our study productivity application. Please read them carefully before creating an account. By using GYAN, you enter into a legal agreement with the GYAN development team.',
        style: GoogleFonts.inder(color: _muted, fontSize: 13, height: 1.7),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Section header ──────────────────────────────────────────────
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _blue.withOpacity(0.3)),
            ),
            alignment: Alignment.center,
            child: Text(number,
                style: GoogleFonts.inder(
                    color: _blue, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: GoogleFonts.inder(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Text(
            content,
            style: GoogleFonts.inder(
                color: Colors.white70, fontSize: 13, height: 1.7),
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: _divider),
      ]),
    );
  }
}