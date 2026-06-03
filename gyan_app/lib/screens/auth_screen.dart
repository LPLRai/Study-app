// ─────────────────────────────────────────────────────────────────────────────
// screens/auth_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'terms_screen.dart';
import 'main_screen.dart';
import 'getstarted_screen.dart'; // ← shown after registration

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _identityController  = TextEditingController();
  final _passwordController  = TextEditingController();
  final _emailController     = TextEditingController();
  final _usernameController  = TextEditingController();

  bool _isRegister      = false;
  bool _termsAccepted   = false;
  bool _isBusy          = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identityController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isBusy = true);

    final prov      = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (_isRegister) {
      // ── Registration flow ────────────────────────────────────────────────
      final success = await prov.register(
        email:    _emailController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isBusy = false);

      if (!success) {
        messenger.showSnackBar(SnackBar(
          content: const Text('Could not register. Check your email and try again.'),
          backgroundColor: AppColors.red,
        ));
        return;
      }

      // Registration succeeded — a verification email was sent automatically
      // by FirebaseService.registerWithEmail (sendEmailVerification).
      // Take the new user straight to GetStartedPage to fill their profile.
      // GetStartedPage will navigate to AuthScreen (login mode) when done.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GetStartedPage()),
      );
    } else {
      // ── Login flow ───────────────────────────────────────────────────────
      final success = await prov.signIn(
        usernameOrEmail: _identityController.text.trim(),
        password:        _passwordController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isBusy = false);

      if (!success) {
        messenger.showSnackBar(SnackBar(
          content: const Text(
              'Login failed. Make sure your email is verified and credentials are correct.'),
          backgroundColor: AppColors.red,
        ));
        return;
      }

      // Login succeeded → go to main app
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  Future<void> _forgotPassword({
    required Color cardColor,
    required Color textColor,
    required Color subtitleColor,
    required Color fillColor,
    required bool isDark,
  }) async {
    final resetEmailCtrl = TextEditingController(
      text: _identityController.text.contains('@')
          ? _identityController.text.trim()
          : '',
    );
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Reset Password',
            style: GoogleFonts.inder(
                color: textColor, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            "Enter your email address and we'll send you a link to reset your password.",
            style: GoogleFonts.inder(
                color: subtitleColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: resetEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: textColor),
            cursorColor: AppColors.blue,
            decoration: InputDecoration(
              hintText: 'your@email.com',
              hintStyle: TextStyle(color: subtitleColor),
              filled: true,
              fillColor: fillColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                    color: AppColors.blue.withOpacity(0.9), width: 1.5),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inder(color: subtitleColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailCtrl.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Please enter a valid email address.')));
                return;
              }
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(
                  content: Text('📧 Reset link sent to $email'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 4),
                ));
              } on FirebaseAuthException catch (e) {
                messenger.showSnackBar(SnackBar(
                  content: Text(e.message ?? 'Something went wrong.'),
                  backgroundColor: AppColors.red,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('Send Link',
                style: GoogleFonts.inder(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    resetEmailCtrl.dispose();
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required Color labelColor,
    required Color textColor,
    required Color fillColor,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.inder(color: labelColor, fontSize: 12)),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: textColor),
        cursorColor: AppColors.blue,
        decoration: InputDecoration(
          filled: true,
          fillColor: fillColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide:
                BorderSide(color: textColor.withOpacity(0.15), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide:
                BorderSide(color: textColor.withOpacity(0.12), width: 1.1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
                color: AppColors.blue.withOpacity(0.9), width: 1.5),
          ),
        ),
        validator: validator,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final prov          = context.watch<AppProvider>();
    final isDark        = prov.isDarkMode;
    final background    = isDark ? const Color(0xFF121318) : const Color(0xFFF5F2F7);
    final cardColor     = isDark ? const Color(0xFF18181F) : Colors.white;
    final textColor     = isDark ? Colors.white : const Color(0xFF1A1A22);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF6E6E78);
    final fillColor     = isDark ? const Color(0xFF232329) : const Color(0xFFF2F0F7);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Stack(children: [
          SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(children: [
              const SizedBox(height: 18),
              const SizedBox(height: 24),
              Center(
                child: Column(children: [
                  SvgPicture.asset(
                    'assets/icon/gyam.svg',
                    width: 120,
                    height: 120,
                    colorFilter: ColorFilter.mode(
                      isDark ? Colors.white : AppColors.blue,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(isDark ? 0.35 : 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isRegister ? 'Create Account' : 'Welcome Back',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inder(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isRegister
                            ? 'Fill in your details, then set up your study profile.'
                            : 'Log in to continue your study streak and sync across devices.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inder(
                            color: subtitleColor,
                            fontSize: 14,
                            height: 1.5),
                      ),
                      const SizedBox(height: 32),

                      // ── Register fields ──────────────────────────────────
                      if (_isRegister) ...[
                        _buildField(
                          label: 'Email',
                          controller: _emailController,
                          obscureText: false,
                          keyboardType: TextInputType.emailAddress,
                          labelColor: subtitleColor,
                          textColor: textColor,
                          fillColor: fillColor,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Enter your email';
                            if (!v.contains('@'))
                              return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        _buildField(
                          label: 'Username',
                          controller: _usernameController,
                          obscureText: false,
                          labelColor: subtitleColor,
                          textColor: textColor,
                          fillColor: fillColor,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Enter a username';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                      // ── Login fields ─────────────────────────────────────
                      ] else ...[
                        _buildField(
                          label: 'Email',
                          controller: _identityController,
                          obscureText: false,
                          keyboardType: TextInputType.emailAddress,
                          labelColor: subtitleColor,
                          textColor: textColor,
                          fillColor: fillColor,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Enter your email';
                            if (!v.contains('@'))
                              return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                      ],

                      _buildField(
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        labelColor: subtitleColor,
                        textColor: textColor,
                        fillColor: fillColor,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: subtitleColor,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Enter your password';
                          if (_isRegister && v.trim().length < 6)
                            return 'Password should be at least 6 characters';
                          return null;
                        },
                      ),

                      if (!_isRegister) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: _isBusy
                                ? null
                                : () => _forgotPassword(
                                      cardColor: cardColor,
                                      textColor: textColor,
                                      subtitleColor: subtitleColor,
                                      fillColor: fillColor,
                                      isDark: isDark,
                                    ),
                            child: Text('Forgot Password?',
                                style: GoogleFonts.inder(
                                  color: AppColors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Terms checkbox (register only) ───────────────────
                      if (_isRegister) ...[
                        Row(children: [
                          Checkbox(
                            value: _termsAccepted,
                            onChanged: (v) =>
                                setState(() => _termsAccepted = v ?? false),
                            activeColor: AppColors.blue,
                            fillColor:
                                WidgetStateProperty.all(AppColors.blue),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const TermsScreen()),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.inder(
                                      color: subtitleColor, fontSize: 12),
                                  children: [
                                    const TextSpan(text: 'I have read the '),
                                    TextSpan(
                                      text: 'Terms and Conditions',
                                      style: GoogleFonts.inder(
                                        color: AppColors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                      ],

                      // ── Submit button ────────────────────────────────────
                      ElevatedButton(
                        onPressed: _isBusy || (_isRegister && !_termsAccepted)
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _isBusy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.2),
                              )
                            : Text(
                                _isRegister ? 'Sign up' : 'Login',
                                style: GoogleFonts.inder(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                      const SizedBox(height: 12),

                      // ── Toggle register ↔ login ──────────────────────────
                      if (_isRegister)
                        OutlinedButton(
                          onPressed: _isBusy
                              ? null
                              : () => setState(() {
                                    _isRegister = false;
                                    _emailController.clear();
                                    _passwordController.clear();
                                    _usernameController.clear();
                                  }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textColor,
                            side: BorderSide(
                                color: textColor.withOpacity(0.2)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text('Already have an account? Login',
                              style: GoogleFonts.inder(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),

                      if (!_isRegister) ...[
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _isBusy
                              ? null
                              : () => setState(() => _isRegister = true),
                          child: Text(
                            'No Account? Register Now!!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inder(
                                color: AppColors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),

          // ── Dark-mode toggle ─────────────────────────────────────────────
          Positioned(
            left: 24,
            bottom: 0,
            child: Row(children: [
              Switch(
                value: prov.isDarkMode,
                onChanged: (v) => prov.setDarkMode(v),
                activeColor: Colors.white,
                activeTrackColor: AppColors.blue,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE8E8F0),
                trackOutlineColor:
                    WidgetStateProperty.all(Colors.transparent),
              ),
              const SizedBox(width: 6),
              Text(
                isDark ? 'Dark Mode' : 'Light Mode',
                style: GoogleFonts.inder(
                    color: subtitleColor, fontSize: 13),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class YourCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}