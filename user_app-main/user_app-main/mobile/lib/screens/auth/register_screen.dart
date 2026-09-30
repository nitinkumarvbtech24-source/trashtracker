import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'map_selection_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_latCtrl.text.isEmpty || _lngCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your location'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_passwordCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    try {
      await auth.register(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        lat: _latCtrl.text.trim(),
        lng: _lngCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } catch (_) {}
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _latCtrl.text = pos.latitude.toString();
      _lngCtrl.text = pos.longitude.toString();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),

                // Glowing Sphere Logo
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white, // White core
                    border: Border.all(color: AppColors.primary.withOpacity(0.8), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.1),
                        blurRadius: 80,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Create Your Account?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your account to explore exciting waste\nmanagement plans and adventures.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 32),

                // Error
                if (auth.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(auth.error!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 13)),
                        ),
                        GestureDetector(
                          onTap: auth.clearError,
                          child: const Icon(Icons.close,
                              color: AppColors.error, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                AppTextField(
                  label: 'Full Name',
                  hint: 'Your full name',
                  controller: _nameCtrl,
                  prefixIcon: Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Name is required' : null,
                ),
                AppTextField(
                  label: 'Username',
                  hint: 'Choose a username',
                  controller: _usernameCtrl,
                  prefixIcon: Icons.alternate_email,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Username is required' : null,
                ),
                AppTextField(
                  label: 'Email Address',
                  hint: 'you@example.com',
                  controller: _emailCtrl,
                  prefixIcon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                AppTextField(
                  label: 'Phone Number',
                  hint: '10-digit mobile number',
                  controller: _phoneCtrl,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.length != 10) return 'Enter 10-digit phone';
                    return null;
                  },
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Home / Default Location', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      Text(
                        _latCtrl.text.isEmpty ? 'No location selected' : 'Selected: ${_latCtrl.text}, ${_lngCtrl.text}',
                        style: TextStyle(color: _latCtrl.text.isEmpty ? Colors.grey : AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _getCurrentLocation,
                              icon: const Icon(Icons.my_location, size: 18),
                              label: const Text('Use Current'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final LatLng? result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MapSelectionScreen()),
                                );
                                if (result != null) {
                                  setState(() {
                                    _latCtrl.text = result.latitude.toString();
                                    _lngCtrl.text = result.longitude.toString();
                                  });
                                }
                              },
                              icon: const Icon(Icons.map, size: 18),
                              label: const Text('Pick on Map'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_latCtrl.text.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text('Location is required for pickup services', style: TextStyle(color: AppColors.error, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Password',
                  hint: 'Min. 8 characters',
                  controller: _passwordCtrl,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Min 8 characters';
                    return null;
                  },
                ),
                AppTextField(
                  label: 'Confirm Password',
                  hint: 'Repeat your password',
                  controller: _confirmCtrl,
                  prefixIcon: Icons.shield_outlined,
                  isPassword: true,
                  validator: (v) {
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),

                AppButton(
                  label: 'Create Account',
                  onPressed: _register,
                  isLoading: auth.isLoading,
                ),
                const SizedBox(height: 16),

                Text.rich(
                  TextSpan(
                    text: 'By signing up, you agree to our ',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                    children: [
                      TextSpan(
                        text: 'Terms of Service',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14)),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
