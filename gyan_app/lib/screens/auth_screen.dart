import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/app_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identityController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isRegister = false;
  bool _termsAccepted = false;
  bool _isBusy = false;

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
    final prov = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = _isRegister
        ? await prov.register(
            email: _emailController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text.trim(),
          )
        : await prov.signIn(
            usernameOrEmail: _identityController.text.trim(),
            password: _passwordController.text.trim(),
          );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isRegister
                ? 'Could not register. Check your email and password.'
                : 'Login failed. Check your credentials.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    } else if (_isRegister) {
      // show after successful registration
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Verification email sent! Please check your inbox before logging in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
      setState(() {
        _isRegister = false;
        _emailController.clear();
        _passwordController.clear();
        _usernameController.clear();
      });
    }
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
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inder(color: labelColor, fontSize: 12)),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: textColor.withOpacity(0.15), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: textColor.withOpacity(0.12), width: 1.1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: AppColors.blue.withOpacity(0.9), width: 1.5),
          ),
        ),
        validator: validator,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AppProvider>();
    final isDark = prov.isDarkMode;
    final background = isDark ? const Color(0xFF121318) : const Color(0xFFF5F2F7);
    final cardColor = isDark ? const Color(0xFF18181F) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A22);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF6E6E78);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Stack(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      _isRegister ? 'Create Account' : 'Welcome Back',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inder(color: textColor, fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isRegister
                          ? 'Create a new account and save your study progress online.'
                          : 'Log in to continue your study streak and sync across devices.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inder(color: subtitleColor, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    if (_isRegister) ...[
                      _buildField(
                        label: 'Email',
                        controller: _emailController,
                        obscureText: false,
                        keyboardType: TextInputType.emailAddress,
                        labelColor: subtitleColor,
                        textColor: textColor,
                        fillColor: isDark ? const Color(0xFF232329) : const Color(0xFFF2F0F7),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter your email';
                          if (!value.contains('@')) return 'Enter a valid email';
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
                        fillColor: isDark ? const Color(0xFF232329) : const Color(0xFFF2F0F7),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter a username';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      _buildField(
                        label: 'Email or Username',
                        controller: _identityController,
                        obscureText: false,
                        keyboardType: TextInputType.emailAddress,
                        labelColor: subtitleColor,
                        textColor: textColor,
                        fillColor: isDark ? const Color(0xFF232329) : const Color(0xFFF2F0F7),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter your email or username';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                    ],
                    _buildField(
                      label: 'Password',
                      controller: _passwordController,
                      obscureText: true,
                      labelColor: subtitleColor,
                      textColor: textColor,
                      fillColor: isDark ? const Color(0xFF232329) : const Color(0xFFF2F0F7),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Enter your password';
                        if (_isRegister && value.trim().length < 6) return 'Password should be at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_isRegister) ...[
                      Row(children: [
                        Checkbox(
                          value: _termsAccepted,
                          onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                          activeColor: AppColors.blue,
                          fillColor: WidgetStateProperty.all(AppColors.blue),
                        ),
                        Expanded(
                          child: Text(
                            'I have read the Terms and Conditions',
                            style: GoogleFonts.inder(color: subtitleColor, fontSize: 12),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isBusy || (_isRegister && !_termsAccepted) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _isBusy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                          : Text(
                              _isRegister ? 'Sign up' : 'Login',
                              style: GoogleFonts.inder(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                    const SizedBox(height: 12),
                    if (_isRegister)
                      OutlinedButton(
                        onPressed: _isBusy ? null : () => setState(() => _isRegister = false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor.withOpacity(0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text('Login', style: GoogleFonts.inder(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    if (!_isRegister) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _isBusy ? null : () => setState(() => _isRegister = true),
                        child: Text(
                          'No Account? Register Now!!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inder(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
          Positioned(
            left: 24,
            bottom: 0,
            child: Row(children: [
              Switch(
                value: prov.isDarkMode,
                onChanged: (value) => prov.setDarkMode(value),
                activeColor: Colors.white,
                activeTrackColor: AppColors.blue,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE8E8F0),
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
              ),
              const SizedBox(width: 6),
              Text(
                isDark ? 'Dark Mode' : 'Light Mode',
                style: GoogleFonts.inder(color: subtitleColor, fontSize: 13),
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
  void paint(Canvas canvas, Size size) {
    // your drawing logic here
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}