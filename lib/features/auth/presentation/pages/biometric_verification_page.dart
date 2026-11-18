import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../data/models/user_model.dart';
import '../../data/services/biometric_service.dart';

class BiometricVerificationPage extends StatefulWidget {
  final BiometricService? biometricService;

  const BiometricVerificationPage({
    super.key,
    this.biometricService,
  });

  @override
  State<BiometricVerificationPage> createState() =>
      _BiometricVerificationPageState();
}

class _BiometricVerificationPageState extends State<BiometricVerificationPage> {
  late final BiometricService _biometricService;
  UserModel? _user;
  bool _isInitializing = true;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _biometricService = widget.biometricService ?? BiometricService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndPrompt();
    });
  }

  Future<void> _initializeAndPrompt() async {
    final user = await LocalStorageService.getUser();
    if (!mounted) return;

    if (user == null || user.userId <= 0) {
      context.go('/login');
      return;
    }

    final alreadyVerified = await LocalStorageService.isBiometricVerified();
    if (!mounted) return;

    if (!user.isPunchNeeded || alreadyVerified) {
      context.go('/dashboard');
      return;
    }

    setState(() {
      _user = user;
      _isInitializing = false;
    });

    await _verifyBiometrics();
  }

  Future<void> _verifyBiometrics() async {
    if (_isVerifying) return;
    final user = _user ?? await LocalStorageService.getUser();
    if (!mounted) return;

    if (user == null || user.userId <= 0) {
      context.go('/login');
      return;
    }

    if (await LocalStorageService.isBiometricVerified() || !user.isPunchNeeded) {
      if (mounted) context.go('/dashboard');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final result = await _biometricService.authenticate(
      localizedReason: 'Verify your biometrics to continue as ${user.userName}',
    );

    if (!mounted) return;

    setState(() {
      _isVerifying = false;
    });

    if (result.isSuccess) {
      await LocalStorageService.setBiometricVerified(true);
      await LocalStorageService.saveLoginTimestamp();
      await LocalStorageService.activateBiometricLockAfterVerification();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: const Color(0xFF081735),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1342A0), Color(0xFF1C64F2)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Welcome back, ${user.userName}!',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      context.go('/dashboard');
      return;
    }

    setState(() {
      _errorMessage = result.isCancelled
          ? 'Biometric verification was cancelled. Tap below to try again.'
          : (result.errorMessage ??
              'Biometric verification failed. Please try again.');
    });
  }

  Future<void> _handleSignOut() async {
    final bioOnly = await LocalStorageService.isBiometricOnlyMode();
    final bioEnabled = await LocalStorageService.isBiometricEnabled();
    if (!bioOnly && !bioEnabled) {
      await LocalStorageService.clearBiometricCredentials();
    }
    await LocalStorageService.clearUserSession();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final userName = _user?.userName ?? '';
    final companyName = _user?.company ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28.0,
              vertical: 24.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/construction_logo.png',
                      height: 82,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Text(
                        AppConstants.appName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFBFDBFE),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        size: 46,
                        color: Color(0xFF1342A0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Biometric Verification',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    userName.isNotEmpty
                        ? 'Hi $userName, verify your biometrics to continue to the dashboard.'
                        : 'Verify your biometrics to continue to the dashboard.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                      height: 1.45,
                    ),
                  ),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          companyName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF081735),
                          Color(0xFF1342A0),
                          Color(0xFF1C64F2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1C64F2).withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: (_isInitializing || _isVerifying)
                            ? null
                            : _verifyBiometrics,
                        borderRadius: BorderRadius.circular(14),
                        child: Center(
                          child: (_isInitializing || _isVerifying)
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Verifying...',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.fingerprint_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Verify with Biometrics',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _isVerifying ? null : _handleSignOut,
                    child: Text(
                      'Sign Out',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

