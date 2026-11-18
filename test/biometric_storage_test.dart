import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_app/core/storage/local_storage_service.dart';

void main() {
  test(
    'Biometric credentials persist across user sign-out and update on password change',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      expect(await LocalStorageService.isBiometricEnabled(), isFalse);
      expect(await LocalStorageService.getBiometricCredentials(), isNull);

      await LocalStorageService.saveBiometricCredentials(
        loginId: 'Joby',
        password: 'welcome',
      );
      await LocalStorageService.setBiometricEnabled(true);

      expect(await LocalStorageService.isBiometricEnabled(), isTrue);
      final creds = await LocalStorageService.getBiometricCredentials();
      expect(creds?.loginId, 'Joby');
      expect(creds?.password, 'welcome');

      // Regular session sign-out keeps biometric login credentials available on LoginPage
      await LocalStorageService.clearUserSession();
      expect(await LocalStorageService.isBiometricEnabled(), isTrue);
      expect((await LocalStorageService.getBiometricCredentials())?.loginId, 'Joby');

      // Updating password updates stored biometric password when enabled
      await LocalStorageService.updateBiometricPasswordIfEnabled('newPass123');
      expect(
        (await LocalStorageService.getBiometricCredentials())?.password,
        'newPass123',
      );

      // Disabling biometric clears stored credentials
      await LocalStorageService.clearBiometricCredentials();
      expect(await LocalStorageService.isBiometricEnabled(), isFalse);
      expect(await LocalStorageService.getBiometricCredentials(), isNull);
    },
  );
}

