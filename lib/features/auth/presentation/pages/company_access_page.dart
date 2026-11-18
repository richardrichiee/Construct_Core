import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/services/access_point_service.dart';

class CompanyAccessPage extends StatefulWidget {
  const CompanyAccessPage({super.key});

  @override
  State<CompanyAccessPage> createState() => _CompanyAccessPageState();
}

class _CompanyAccessPageState extends State<CompanyAccessPage> {
  final _accessIdController = TextEditingController();
  final _accessPointService = AccessPointService();
  bool _isLoading = false;
  String? _errorMessage;
  String? _fetchedAccessPoint;

  Future<void> _handleVerifyAccessPoint() async {
    final accessId = _accessIdController.text.trim();
    if (accessId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your Company Access ID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _fetchedAccessPoint = null;
    });

    final result = await _accessPointService.fetchAccessPoint(accessId);

    setState(() {
      _isLoading = false;
    });

    if (result.isSuccess) {
      setState(() {
        _fetchedAccessPoint = result.accessPoint;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        // Navigate to Dashboard after 1 second
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            context.go('/login');
          }
        });
      }
    } else {
      setState(() {
        _errorMessage = result.errorMessage ?? 'Failed to connect.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo
                Center(
                  child: Image.asset(
                    'assets/images/construction_logo.png',
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.apartment_rounded,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Access ID Input Field
                TextField(
                  controller: _accessIdController,
                  decoration: InputDecoration(
                    labelText: 'Company Access ID',
                    hintText: 'Enter Company Access ID',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Error Message Display
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),

                // Success AccessPoint Display
                if (_fetchedAccessPoint != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Connected successfully!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),

                // Connect Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerifyAccessPoint,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
