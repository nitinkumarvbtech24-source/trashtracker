import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';

import '../screens/dashboard/home_map_screen.dart';
import '../screens/report/report_issue_screen.dart';

import '../screens/ondemand/book_ondemand_screen.dart';
import '../screens/ondemand/rider_matching_screen.dart';
import '../screens/ondemand/live_tracking_screen.dart';
import '../screens/ondemand/payment_screen.dart';

import '../screens/profile/profile_screen.dart';

class AppRouter {
  static CustomTransitionPage _buildTransition(Widget child, LocalKey? key) {
    return CustomTransitionPage(
      key: key,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.05),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutQuart,
            )),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static GoRouter createRouter(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final isAuth = auth.isAuthenticated;
        final isInitializing = auth.isInitializing;
        final path = state.matchedLocation;

        if (isInitializing) return '/splash';

        if (path == '/splash') {
          return isAuth ? '/home' : '/login';
        }

        final isAuthRoute = path == '/login' || path == '/register';

        if (!isAuth && !isAuthRoute) return '/login';
        if (isAuth && isAuthRoute) return '/home';

        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          pageBuilder: (_, state) => _buildTransition(const SplashScreen(), state.pageKey),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (_, state) => _buildTransition(const LoginScreen(), state.pageKey),
        ),
        GoRoute(
          path: '/register',
          pageBuilder: (_, state) => _buildTransition(const RegisterScreen(), state.pageKey),
        ),

        // Main shell with bottom nav
        ShellRoute(
          pageBuilder: (context, state, child) => _buildTransition(MainShell(child: child), state.pageKey),
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (_, state) => _buildTransition(const HomeMapScreen(), state.pageKey),
            ),
            GoRoute(
              path: '/report',
              pageBuilder: (_, state) => _buildTransition(const ReportIssueScreen(), state.pageKey),
            ),

            GoRoute(
              path: '/book',
              pageBuilder: (_, state) => _buildTransition(const BookOndemandScreen(), state.pageKey),
            ),
          ],
        ),

        // On-Demand Full Screen Flows
        GoRoute(
          path: '/matching',
          pageBuilder: (_, state) => _buildTransition(const RiderMatchingScreen(), state.pageKey),
        ),
        GoRoute(
          path: '/tracking_live',
          pageBuilder: (_, state) => _buildTransition(const LiveTrackingScreen(), state.pageKey),
        ),
        GoRoute(
          path: '/payment',
          pageBuilder: (_, state) => _buildTransition(const PaymentScreen(), state.pageKey),
        ),

        // Keep profile routes if needed
        GoRoute(
          path: '/profile',
          pageBuilder: (_, state) => _buildTransition(const ProfileScreen(), state.pageKey),
        ),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _routes = ['/home', '/report', '/book'];

  void _onTap(int index) {
    if (_selectedIndex == index) {
      Navigator.pop(context);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);
    context.go(_routes[index]);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.primary,
              ),
              child: const Text(
                'Take My Trash',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: Icon(_selectedIndex == 0 ? Icons.map : Icons.map_outlined,
                  color: _selectedIndex == 0 ? AppColors.primary : AppColors.textSecondary),
              title: Text('Home', 
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans', 
                  fontWeight: _selectedIndex == 0 ? FontWeight.w800 : FontWeight.normal,
                  color: _selectedIndex == 0 ? AppColors.primary : AppColors.textPrimary,
                )
              ),
              onTap: () => _onTap(0),
            ),
            ListTile(
              leading: Icon(_selectedIndex == 1 ? Icons.camera_alt : Icons.camera_alt_outlined,
                  color: _selectedIndex == 1 ? AppColors.primary : AppColors.textSecondary),
              title: Text('Report', 
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans', 
                  fontWeight: _selectedIndex == 1 ? FontWeight.w800 : FontWeight.normal,
                  color: _selectedIndex == 1 ? AppColors.primary : AppColors.textPrimary,
                )
              ),
              onTap: () => _onTap(1),
            ),
            ListTile(
              leading: Icon(_selectedIndex == 2 ? Icons.local_shipping : Icons.local_shipping_outlined,
                  color: _selectedIndex == 2 ? AppColors.primary : AppColors.textSecondary),
              title: Text('Book', 
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans', 
                  fontWeight: _selectedIndex == 2 ? FontWeight.w800 : FontWeight.normal,
                  color: _selectedIndex == 2 ? AppColors.primary : AppColors.textPrimary,
                )
              ),
              onTap: () => _onTap(2),
            ),
          ],
        ),
      ),
      body: widget.child,
    );
  }
}
