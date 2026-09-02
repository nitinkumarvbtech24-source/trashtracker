import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _vehicleNoController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    final authService = context.read<AuthService>();
    final result = await authService.login(
      _vehicleNoController.text.trim(),
      _mobileController.text.trim(),
      _passwordController.text.trim(),
    );
    
    if (mounted) {
      setState(() => _isLoading = false);
      if (result == LoginResult.success) {
        // Navigation is handled reactively by main.dart listening to AuthService
      } else if (result == LoginResult.alreadyLoggedIn) {
        _showForceLoginDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.withOpacity(0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('Invalid credentials. Please try again.', style: GoogleFonts.inter(color: Colors.white)),
          ),
        );
      }
    }
  }

  void _showForceLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Account Active on Another Device', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text('This account is currently logged in on another device. Do you want to log out the other device and log in here?', style: GoogleFonts.inter(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                setState(() => _isLoading = true);
                final authService = this.context.read<AuthService>();
                final result = await authService.forceLogin(
                  _vehicleNoController.text.trim(),
                  _mobileController.text.trim(),
                  _passwordController.text.trim(),
                );
                if (mounted) {
                  setState(() => _isLoading = false);
                  if (result == LoginResult.success) {
                    // Navigation handled reactively by main.dart
                  } else {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.redAccent.withOpacity(0.9),
                        content: Text('Failed to login.', style: GoogleFonts.inter(color: Colors.white)),
                      ),
                    );
                  }
                }
              },
              child: Text('Force Logout & Login', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final urlController = TextEditingController(text: GARBAGE_AI_URL);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: Text('Backend Settings', style: GoogleFonts.inter(color: Colors.white)),
        content: TextField(
          controller: urlController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Server URL',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                await prefs.setString('garbage_ai_url', newUrl);
                GARBAGE_AI_URL = newUrl;
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, TextInputType type = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: type,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.white54),
          prefixIcon: Icon(icon, color: Colors.blueAccent.withOpacity(0.8)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Premium Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF020617)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Decorative Orbs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.2),
              ),
            ).animateBackground(),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purpleAccent.withOpacity(0.15),
              ),
            ).animateBackground(),
          ),
          
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70),
              onPressed: () => _showSettingsDialog(context),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.local_shipping_rounded, size: 64, color: Colors.blueAccent),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Driver Portal',
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Securely sign in using your AIQ Authority credentials',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: Colors.white70,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                            _buildTextField(_vehicleNoController, 'Vehicle Registration', Icons.directions_car_rounded),
                            const SizedBox(height: 16),
                            _buildTextField(_mobileController, 'Phone Number', Icons.phone_rounded, type: TextInputType.phone),
                            const SizedBox(height: 16),
                            _buildTextField(_passwordController, 'Password', Icons.lock_rounded, isPassword: true),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 8,
                                  shadowColor: Colors.blueAccent.withOpacity(0.5),
                                ),
                                onPressed: _isLoading ? null : _handleLogin,
                                child: _isLoading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text('Log In', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension BackgroundAnimation on Widget {
  Widget animateBackground() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(seconds: 10),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 1.0 + 0.1 * (value),
          child: child,
        );
      },
      child: this,
    );
  }
}
