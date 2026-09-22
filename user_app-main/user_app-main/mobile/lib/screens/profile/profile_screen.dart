import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign Out', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 24),

              // User Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: Center(child: Text(user?.name[0].toUpperCase() ?? 'U', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? 'User', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(user?.email ?? '', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text('📱 ${user?.phone ?? ''}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (user?.isVerified ?? false)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
                        child: const Text('✓ Verified', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Menu
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    _MenuItem(icon: Icons.person_outline, label: 'Edit Profile', onTap: () => context.push('/edit-profile')),
                    const Divider(height: 1),
                    _MenuItem(icon: Icons.shield_outlined, label: 'Privacy & Security', onTap: () => context.push('/privacy')),
                    const Divider(height: 1),
                    _MenuItem(icon: Icons.notifications_none, label: 'Notifications', onTap: () => context.push('/notifications')),
                    const Divider(height: 1),
                    _MenuItem(icon: Icons.help_outline, label: 'Help & Support', onTap: () => context.push('/help')),
                    const Divider(height: 1),
                    _MenuItem(icon: Icons.description_outlined, label: 'Terms of Service', onTap: () => context.push('/terms')),
                    const Divider(height: 1),
                    _MenuItem(icon: Icons.info_outline, label: 'About TakeMyTrash', onTap: () => context.push('/about')),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              AppButton(
                label: 'Sign Out',
                variant: AppButtonVariant.outline,
                onPressed: () => _handleLogout(context),
              ),
              const SizedBox(height: 24),

              const Center(child: Text('TakeMyTrash v1.0.0', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
    );
  }
}
