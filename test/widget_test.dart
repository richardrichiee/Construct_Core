// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const ConstructionApp());

    // Verify that the Splash screen renders cleanly with the Construction logo
    expect(find.text('Powered by'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    // Advance past SplashPage minimum 2.5s timer and settle navigation
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Verify CompanyAccessPage renders logo image & Access ID field
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Company Access ID'), findsOneWidget);
  });
}
