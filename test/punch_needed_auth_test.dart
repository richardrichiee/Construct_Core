import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_app/core/storage/local_storage_service.dart';
import 'package:construction_app/features/auth/data/models/user_model.dart';
import 'package:construction_app/features/auth/data/services/auth_service.dart';
import 'package:construction_app/features/auth/data/services/biometric_service.dart';
import 'package:construction_app/features/auth/presentation/pages/biometric_verification_page.dart';
import 'package:construction_app/features/auth/presentation/pages/login_page.dart';
import 'package:construction_app/features/auth/presentation/pages/splash_page.dart';

class _FakeBiometricService extends BiometricService {
  final List<BiometricAuthResult> results;
  int callCount = 0;

  _FakeBiometricService(this.results);

  @override
  Future<bool> isBiometricAvailable() async => true;

  @override
  Future<BiometricAuthResult> authenticate({
    String localizedReason = 'Verify your identity to sign in',
  }) async {
    final index = callCount < results.length ? callCount : results.length - 1;
    callCount++;
    return results[index];
  }
}

class _FakeAuthService extends AuthService {
  final LoginResult result;

  _FakeAuthService(this.result);

  @override
  Future<LoginResult> login({
    required String loginId,
    required String password,
  }) async {
    await LocalStorageService.saveUser(result.user!);
    await LocalStorageService.setBiometricVerified(false);
    return result;
  }
}

UserModel _makeUser({required int punchNeeded}) => UserModel(
      company: 'Arching Infratech',
      userId: 4,
      userName: 'Joby',
      employeeId: 0,
      serverDate: '12/11/2026',
      roleId: 4,
      onlinePunchAnywhere: 0,
      punchNeeded: punchNeeded,
    );

Widget _buildRouterApp({
  required String initialLocation,
  required BiometricService biometricService,
  AuthService? authService,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/biometric-verify',
        builder: (context, state) => BiometricVerificationPage(
          biometricService: biometricService,
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('DASHBOARD_SCREEN')),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          reason: state.uri.queryParameters['reason'],
          biometricService: biometricService,
          authService: authService,
          autoPromptBiometric: false,
        ),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PunchNeeded flag & verification state', () {
    test('UserModel parses PunchNeeded variations and serializes cleanly', () {
      final activeInt = UserModel.fromJson({
        'Company': 'Arching Infratech',
        'UserID': 4,
        'UserName': 'Joby',
        'EmployeeID': 0,
        'ServerDate': '12/11/2026',
        'RoleID': 4,
        'OnlinePunchAnywhere': 0,
        'PunchNeeded': 1,
      });
      expect(activeInt.punchNeeded, 1);
      expect(activeInt.isPunchNeeded, isTrue);
      expect(activeInt.toJson()['PunchNeeded'], 1);

      final activeBool = UserModel.fromJson({'PunchNeeded': true});
      expect(activeBool.isPunchNeeded, isTrue);

      final inactive = UserModel.fromJson({'PunchNeeded': 0});
      expect(inactive.punchNeeded, 0);
      expect(inactive.isPunchNeeded, isFalse);

      final missing = UserModel.fromJson({});
      expect(missing.punchNeeded, 0);
      expect(missing.isPunchNeeded, isFalse);
    });

    test(
      'LocalStorageService tracks biometric verified state & daily session expiry',
      () async {
        expect(await LocalStorageService.isBiometricVerified(), isFalse);
        expect(await LocalStorageService.isSessionExpiredForNewDay(), isTrue);

        final todayMorning = DateTime(2026, 11, 12, 8, 30);
        final todayEvening = DateTime(2026, 11, 12, 22, 45);
        final tomorrowMorning = DateTime(2026, 11, 13, 7, 0);

        await LocalStorageService.saveUser(_makeUser(punchNeeded: 1));
        await LocalStorageService.saveBiometricCredentials(
          loginId: 'Joby',
          password: 'secret',
        );
        await LocalStorageService.activateBiometricLockAfterVerification();
        await LocalStorageService.setBiometricVerified(true);
        await LocalStorageService.saveLoginTimestamp(timestamp: todayMorning);

        expect(await LocalStorageService.isBiometricVerified(), isTrue);
        expect(await LocalStorageService.isBiometricOnlyMode(), isTrue);
        expect(
          await LocalStorageService.isSessionExpiredForNewDay(now: todayEvening),
          isFalse,
        );
        expect(
          await LocalStorageService.isSessionExpiredForNewDay(
            now: tomorrowMorning,
          ),
          isTrue,
        );

        // Daily invalidation clears session/timestamp/verified flag while preserving biometric-only login lock
        await LocalStorageService.invalidateSessionForNewDay();
        expect(await LocalStorageService.isLoggedIn(), isFalse);
        expect(await LocalStorageService.getUser(), isNull);
        expect(await LocalStorageService.getLoginTimestamp(), isNull);
        expect(await LocalStorageService.isBiometricVerified(), isFalse);
        expect(await LocalStorageService.isBiometricOnlyMode(), isTrue);
        expect(
          (await LocalStorageService.getBiometricCredentials())?.loginId,
          'Joby',
        );
      },
    );
  });

  group('BiometricVerificationPage flow', () {
    testWidgets(
      'verifies biometrics when PunchNeeded=1, saves timestamp & biometric-only lock, and opens dashboard',
      (tester) async {
        await LocalStorageService.saveUser(_makeUser(punchNeeded: 1));
        await LocalStorageService.saveBiometricCredentials(
          loginId: 'Joby',
          password: 'secret',
        );
        await LocalStorageService.setBiometricVerified(false);

        final fakeBio = _FakeBiometricService([
          const BiometricAuthResult(isSuccess: true),
        ]);

        await tester.pumpWidget(
          _buildRouterApp(
            initialLocation: '/biometric-verify',
            biometricService: fakeBio,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeBio.callCount, 1);
        expect(await LocalStorageService.isBiometricVerified(), isTrue);
        expect(await LocalStorageService.isBiometricOnlyMode(), isTrue);
        expect(await LocalStorageService.getLoginTimestamp(), isNotNull);
        expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      },
    );

    testWidgets(
      'bypasses biometric prompt and goes straight to dashboard when already verified',
      (tester) async {
        await LocalStorageService.saveUser(_makeUser(punchNeeded: 1));
        await LocalStorageService.setBiometricVerified(true);

        final fakeBio = _FakeBiometricService([
          const BiometricAuthResult(isSuccess: true),
        ]);

        await tester.pumpWidget(
          _buildRouterApp(
            initialLocation: '/biometric-verify',
            biometricService: fakeBio,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeBio.callCount, 0);
        expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      },
    );

    testWidgets(
      'stays on verification screen on failure, retries on tap, and reaches dashboard',
      (tester) async {
        await LocalStorageService.saveUser(_makeUser(punchNeeded: 1));
        await LocalStorageService.setBiometricVerified(false);

        final fakeBio = _FakeBiometricService([
          const BiometricAuthResult(
            isSuccess: false,
            isCancelled: true,
          ),
          const BiometricAuthResult(isSuccess: true),
        ]);

        await tester.pumpWidget(
          _buildRouterApp(
            initialLocation: '/biometric-verify',
            biometricService: fakeBio,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeBio.callCount, 1);
        expect(find.text('Biometric Verification'), findsOneWidget);
        expect(find.text('Verify with Biometrics'), findsOneWidget);
        expect(await LocalStorageService.isBiometricVerified(), isFalse);

        await tester.tap(find.text('Verify with Biometrics'));
        await tester.pumpAndSettle();

        expect(fakeBio.callCount, 2);
        expect(await LocalStorageService.isBiometricVerified(), isTrue);
        expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      },
    );
  });

  group('Password-based login & emulator compatibility', () {
    testWidgets(
      'LoginPage renders Login ID and Password form for emulator without forcing biometric lock',
      (tester) async {
        await LocalStorageService.saveAccessPoint('http://example.com');
        await LocalStorageService.saveBiometricCredentials(
          loginId: 'Joby',
          password: 'secret',
        );

        final fakeBio = _FakeBiometricService([
          const BiometricAuthResult(isSuccess: true),
        ]);
        final fakeAuth = _FakeAuthService(
          LoginResult(
            isSuccess: true,
            user: _makeUser(punchNeeded: 1),
          ),
        );

        await tester.pumpWidget(
          _buildRouterApp(
            initialLocation: '/login',
            biometricService: fakeBio,
            authService: fakeAuth,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Welcome!'), findsOneWidget);
        expect(find.text('Login ID'), findsOneWidget);
        expect(find.text('Password'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'Joby');
        await tester.enterText(find.byType(TextField).at(1), 'secret');
        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      },
    );

    testWidgets(
      'SplashPage routes to dashboard when user session is active',
      (tester) async {
        await LocalStorageService.saveUser(_makeUser(punchNeeded: 1));
        await LocalStorageService.saveLoginTimestamp(timestamp: DateTime.now());

        final fakeBio = _FakeBiometricService([
          const BiometricAuthResult(isSuccess: true),
        ]);

        await tester.pumpWidget(
          _buildRouterApp(
            initialLocation: '/',
            biometricService: fakeBio,
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      },
    );
  });
}
