import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_app/features/attendance/data/models/daily_attendance_models.dart';
import 'package:construction_app/features/attendance/data/services/daily_attendance_service.dart';
import 'package:construction_app/features/attendance/presentation/pages/daily_attendance_page.dart';
import 'package:construction_app/features/dashboard/data/models/branch_model.dart';
import 'package:construction_app/features/dashboard/data/services/branch_service.dart';

class MockDailyAttendanceService extends DailyAttendanceService {
  List<CalculationPeriodItem> mockPeriods = [
    const CalculationPeriodItem(
      id: 121,
      startDate: '08/11/2026',
      endDate: '14/11/2026',
    ),
  ];
  List<String> mockDates = ['08/11/2026', '09/11/2026', '10/11/2026'];
  List<LabourCategoryItem> mockCategories = [
    const LabourCategoryItem(id: 1, name: 'Barbender'),
    const LabourCategoryItem(id: 2, name: 'Barbender Helper'),
  ];
  List<LabourGroupItem> mockGroups = [
    const LabourGroupItem(id: 10, name: 'Mason Team A'),
  ];
  List<DailyAttendanceWorkerItem> mockWorkers = [
    DailyAttendanceWorkerItem(
      dailyAttendId: 501,
      employeeId: '1432',
      employeeName: 'A-1 - 2432',
      labourCode: '2432',
      category: 'Barbender',
      inTime: '08:00',
      inTimeMr: 'AM',
      outTime: '06:00',
      outTimeMr: 'PM',
      date: '08/11/2026',
    ),
    DailyAttendanceWorkerItem(
      dailyAttendId: 502,
      employeeId: '1433',
      employeeName: 'A-2 - 2433',
      labourCode: '2433',
      category: 'Barbender',
      inTime: '',
      inTimeMr: 'AM',
      outTime: '',
      outTimeMr: 'PM',
      date: '08/11/2026',
    ),
  ];

  bool saveCalled = false;
  bool deleteCalled = false;

  @override
  Future<List<CalculationPeriodItem>> fetchCalculationPeriods({int? branchId, int page = 1}) async {
    return mockPeriods;
  }

  @override
  Future<List<String>> fetchDatesForPeriod(int calcPeriodId) async {
    return mockDates;
  }

  @override
  Future<List<LabourCategoryItem>> fetchLabourCategories({int page = 1}) async {
    return mockCategories;
  }

  @override
  Future<List<LabourGroupItem>> fetchLabourGroups({int page = 1}) async {
    return mockGroups;
  }

  @override
  Future<List<DailyAttendanceWorkerItem>> fetchDailyAttendance({
    required int calcPeriodId,
    required int branchId,
    required String date,
    int groupId = 0,
    int categoryId = 0,
  }) async {
    return mockWorkers;
  }

  @override
  Future<({bool isSuccess, String? errorMessage, dynamic rawResponse})> saveDailyAttendance({
    int id = 0,
    required int calcId,
    required int branchId,
    required String date,
    required List<DailyAttendanceWorkerItem> workers,
    int finYearId = 1,
  }) async {
    saveCalled = true;
    return (isSuccess: true, errorMessage: null, rawResponse: null);
  }

  @override
  Future<({bool isSuccess, String? errorMessage})> deleteDailyAttendance(int id) async {
    deleteCalled = true;
    return (isSuccess: true, errorMessage: null);
  }
}

class MockBranchService extends BranchService {
  @override
  Future<List<BranchModel>> fetchBranches() async {
    return [
      BranchModel(value: 44, name: 'AAA-PARAVUR (26-27)'),
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_point': 'tstConstructions',
      'selected_branch_id': 44,
    });
  });

  group('Daily Attendance Models', () {
    test('CalculationPeriodItem parses json correctly', () {
      final item = CalculationPeriodItem.fromJson({
        'Key': '121',
        'PeriodStartDate': '08/11/2026',
        'PeriodEndDate': '14/11/2026',
      });
      expect(item.id, 121);
      expect(item.startDate, '08/11/2026');
      expect(item.endDate, '14/11/2026');
      expect(item.label, '08/11/2026 - 14/11/2026');

      // Test mobile API format: Value & Name
      final mobileItem = CalculationPeriodItem.fromJson({
        'Value': 138,
        'Name': '01/11/2026 - 07/11/2026',
      });
      expect(mobileItem.id, 138);
      expect(mobileItem.startDate, '01/11/2026');
      expect(mobileItem.endDate, '07/11/2026');
      expect(mobileItem.label, '01/11/2026 - 07/11/2026');
    });

    test('LabourCategoryItem and LabourGroupItem parse correctly', () {
      final cat = LabourCategoryItem.fromJson({
        'CategoryID': '5',
        'LabourCategoryName': 'Carpenter',
      });
      expect(cat.id, 5);
      expect(cat.name, 'Carpenter');

      final grp = LabourGroupItem.fromJson({
        'GroupID': '12',
        'LabourGroupName': 'Carpentry Team',
      });
      expect(grp.id, 12);
      expect(grp.name, 'Carpentry Team');
    });

    test('DailyAttendanceWorkerItem parses 24hr time and normalizes to 12hr AM/PM', () {
      final worker = DailyAttendanceWorkerItem.fromJson({
        'DailyAttendID': '101',
        'EmployeeID': '1432',
        'EmployeeName': 'A-1 - 2432',
        'InTime': '8:00',
        'OutTime': '18:00',
        'Date': '2026-11-08',
      });

      expect(worker.dailyAttendId, 101);
      expect(worker.employeeId, '1432');
      expect(worker.employeeName, 'A-1 - 2432');
      expect(worker.labourCode, '2432');
      expect(worker.inTime, '08:00');
      expect(worker.inTimeMr, 'AM');
      expect(worker.outTime, '06:00');
      expect(worker.outTimeMr, 'PM');

      // Test format back to 24-hr for backend Save API
      expect(worker.formattedInTimeForSave, '08:00');
      expect(worker.formattedOutTimeForSave, '18:00');

      final tailJson = worker.toTailJson(targetDate: '08/11/2026');
      expect(tailJson['EmployeeID'], '1432');
      expect(tailJson['InTime'], '08:00');
      expect(tailJson['OutTime'], '18:00');
      expect(tailJson['Date'], '2026-11-08');
    });

    test('DailyAttendanceWorkerItem handles ISO datetime and converts date correctly', () {
      final worker = DailyAttendanceWorkerItem.fromJson({
        'DailyAttendID': '200',
        'EmployeeID': '1704',
        'EmployeeName': 'Dipankar Barman',
        'LabourCode': '2704',
        'InTime': '2026-11-01T08:30:00',
        'OutTime': '01/11/2026 17:45:00',
        'Date': '01/11/2026',
      });

      expect(worker.inTime, '08:30');
      expect(worker.inTimeMr, 'AM');
      expect(worker.outTime, '05:45');
      expect(worker.outTimeMr, 'PM');

      expect(DailyAttendanceWorkerItem.formatDateToIso('01/11/2026'), '2026-11-01');
      expect(DailyAttendanceWorkerItem.formatDateToIso('2026-11-01'), '2026-11-01');
    });
  });

  group('DailyAttendancePage Widget Tests', () {
    testWidgets('renders daily attendance page and workers', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Title, Calculation Period, and Compact Date Chip
      expect(find.text('Daily Attendance'), findsWidgets);
      expect(find.text('08/11/2026 - 14/11/2026'), findsOneWidget);
      expect(find.text('08'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);

      // Verify Workers loaded
      expect(find.text('A-1 - 2432'), findsOneWidget);
      expect(find.text('A-2 - 2433'), findsOneWidget);
      expect(find.text('2 Workers'), findsOneWidget);

      // Verify Save button
      expect(find.text('Save Attendance'), findsOneWidget);
    });

    testWidgets('Quick fill sets 8 AM - 6 PM on empty worker times', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially worker 2 has --:--
      expect(find.text('--:--'), findsNWidgets(2)); // in and out of worker 2

      // Tap Quick Fill
      await tester.tap(find.text('Fill 8 AM - 6 PM'));
      await tester.pumpAndSettle();

      // Worker 2 should now have 08:00 and 06:00
      expect(find.text('--:--'), findsNothing);
    });

    testWidgets('Tapping Save triggers service saveDailyAttendance', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Attendance'));
      await tester.pumpAndSettle();

      expect(mockService.saveCalled, isTrue);
      expect(find.text('Daily Attendance saved successfully!'), findsOneWidget);
    });

    testWidgets('Tapping Delete triggers service deleteDailyAttendance and shows success', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Delete icon button
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Dialog shows with confirmation
      expect(find.text('Delete Daily Attendance'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deleteCalled, isTrue);
      expect(find.text('Daily Attendance deleted successfully.'), findsOneWidget);
    });

    testWidgets('Search query filters the worker list', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), '2432');
      await tester.pumpAndSettle();

      // Worker 1 should remain, Worker 2 should be filtered out
      expect(find.text('A-1 - 2432'), findsOneWidget);
      expect(find.text('A-2 - 2433'), findsNothing);
      expect(find.text('1 Workers'), findsOneWidget);
    });

    testWidgets('Tapping Filter opens modal and shows Labour Group & Category', (tester) async {
      final mockService = MockDailyAttendanceService();
      final mockBranchService = MockBranchService();

      await tester.pumpWidget(
        MaterialApp(
          home: DailyAttendancePage(
            dailyAttendanceService: mockService,
            branchService: mockBranchService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Filter button
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();

      // Filter bottom sheet opens
      expect(find.text('Filter Workers'), findsOneWidget);
      expect(find.text('LABOUR GROUP'), findsOneWidget);
      expect(find.text('LABOUR CATEGORY'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);

      // Tap Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Sheet closes
      expect(find.text('Filter Workers'), findsNothing);
    });
  });
}

