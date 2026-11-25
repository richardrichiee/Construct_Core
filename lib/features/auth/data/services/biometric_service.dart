import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? errorMessage;

  const BiometricAuthResult({
    required this.isSuccess,
    this.isCancelled = false,
    this.errorMessage,
  });
}

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    try {
      if (kIsWeb) return false;
      final bool supported = await _auth.isDeviceSupported();
      if (supported) return true;

      final bool canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricAuthResult> authenticate({
    String localizedReason = 'Verify your identity to sign in',
  }) async {
    try {
      final bool available = await isBiometricAvailable();
      if (!available) {
        return const BiometricAuthResult(
          isSuccess: false,
          errorMessage:
              'Device unlock is not set up on this phone. Please set up Face ID, fingerprint, or a device passcode/PIN in Settings.',
        );
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        return const BiometricAuthResult(isSuccess: true);
      }
      return const BiometricAuthResult(
        isSuccess: false,
        errorMessage: 'Biometric authentication did not succeed.',
      );
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.userRequestedFallback:
          return const BiometricAuthResult(
            isSuccess: false,
            isCancelled: true,
          );
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          return const BiometricAuthResult(
            isSuccess: false,
            errorMessage:
                'No biometric or device passcode/PIN is set up in your phone Settings.',
          );
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          return const BiometricAuthResult(
            isSuccess: false,
            errorMessage: 'Biometric sensor is unavailable on this device.',
          );
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return const BiometricAuthResult(
            isSuccess: false,
            errorMessage:
                'Biometric unlock is temporarily locked after too many attempts. Please sign in with your password.',
          );
        case LocalAuthExceptionCode.authInProgress:
          return const BiometricAuthResult(
            isSuccess: false,
            isCancelled: true,
          );
        default:
          return BiometricAuthResult(
            isSuccess: false,
            errorMessage: e.description?.isNotEmpty == true
                ? e.description
                : 'Biometric authentication failed. Please try again.',
          );
      }
    } on PlatformException catch (e) {
      return BiometricAuthResult(
        isSuccess: false,
        errorMessage: e.message ?? 'Biometric authentication failed.',
      );
    } catch (_) {
      return const BiometricAuthResult(
        isSuccess: false,
        errorMessage: 'Biometric authentication failed. Please try again.',
      );
    }
  }
}

