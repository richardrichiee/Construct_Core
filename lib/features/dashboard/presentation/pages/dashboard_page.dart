import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../attendance/data/services/attendance_service.dart';
import '../../../attendance/data/models/attendance_log_model.dart';
import '../../../attendance/data/models/last_attendance_model.dart';
import '../../../profile/data/services/employee_service.dart';
import '../../../profile/data/models/employee_details_model.dart';
import '../../data/models/branch_model.dart';
import '../../data/models/financial_year_model.dart';
import '../../data/models/menu_item_model.dart';
import '../../data/services/branch_service.dart';
import '../../data/services/financial_year_service.dart';
import '../../data/services/menu_service.dart';
import '../../data/services/notification_service.dart';
import '../../../leave/data/models/leave_application_model.dart';
import '../../../leave/data/services/leave_service.dart';
import '../../../auth/data/models/user_rights_model.dart';
import '../../../auth/data/services/access_point_service.dart';
import '../../../auth/data/services/user_rights_service.dart';
import '../widgets/attendance_calendar_widget.dart';
import '../widgets/dashboard_metrics.dart';
import '../widgets/leave_balance_chart.dart';
import '../widgets/today_punch_history_sheet.dart';
import '../../../settings/presentation/widgets/branch_location_sheet.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _branchService = BranchService();
  final _financialYearService = FinancialYearService();
  final _employeeService = EmployeeService();
  final _attendanceService = AttendanceService();
  final _notificationService = NotificationService();
  final _menuService = MenuService();
  final _userRightsService = UserRightsService();

  bool _isCheckedIn = false;
  bool _isLocationChecking = false;
  bool _isMenuLoading = true;
  bool _canViewLeave = false;
  bool _canViewClaims = false;
  bool _hasResolvedUser = false;
  bool _hasLinkedEmployee = false;
  List<MenuItemModel> _menuItems = [];
  String _checkInTime = '--:--';
  String _checkOutTime = '';
  String _rawCheckInTime = '';
  String _userName = '';
  String _userDesignation = '';
  String _userAvatarLetter = '';
  String? _companyImageUrl;

  List<BranchModel> _branches = [];
  BranchModel? _selectedBranch;

  List<FinancialYearModel> _financialYears = [];
  FinancialYearModel? _selectedFinancialYear;

  final Map<int, Color> _liveDayStatus = {};
  final Map<int, Map<String, String>> _liveDayDetails = {};
  int _attendanceCount = 0;
  num _leavesCount = 0;
  int _notificationCount = 0;
  List<LeaveSummaryItem> _leaveSummaryItems = [];

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 1. Immediately show cached user info, cached branches & selected branch
    final user = await LocalStorageService.getUser();
    final cachedBranches = await LocalStorageService.getBranches();
    final cachedMenus = await LocalStorageService.getMenus();
    final savedBranchId = await LocalStorageService.getSelectedBranchId();
    final cachedCompanyLogo = await LocalStorageService.getCompanyImageUrl();
    await LocalStorageService.clearPunchCache();

    if (mounted) {
      setState(() {
        _hasResolvedUser = true;
        _hasLinkedEmployee = (user?.employeeId ?? 0) > 0;
        if (cachedMenus.isNotEmpty && _menuItems.isEmpty) {
          _menuItems = cachedMenus;
        }
        if (cachedCompanyLogo != null && cachedCompanyLogo.isNotEmpty) {
          _companyImageUrl = cachedCompanyLogo;
        }
        if (user != null && _userName.isEmpty) {
          _userName = user.userName;
          _userAvatarLetter = user.userName.isNotEmpty
              ? user.userName[0].toUpperCase()
              : 'U';
        }
        if (cachedBranches.isNotEmpty && _branches.isEmpty) {
          _branches = cachedBranches;
          if (savedBranchId != null) {
            _selectedBranch = _branches.firstWhere(
              (b) => b.value == savedBranchId,
              orElse: () => _branches.first,
            );
          } else {
            _selectedBranch = _branches.first;
          }
        }
      });
    }

    if (_companyImageUrl == null || _companyImageUrl!.isEmpty) {
      AccessPointService().ensureCompanyImageUrl().then((img) {
        if (mounted && img != null && img.isNotEmpty) {
          setState(() {
            _companyImageUrl = img;
          });
        }
      });
    }

    final leaveService = LeaveService();
    final empId = user?.employeeId;

    // Resolve branches first on fresh login (when no branch is cached/selected yet)
    // so fetchLastAttendance & fetchHistoryAttendance use the user's real BranchID
    // instead of defaulting to 1 (which caused Check-In to show after logout -> login).
    List<BranchModel>? prefetchedBranches;
    int? resolvedBranchId = _selectedBranch?.id ?? savedBranchId;
    if (resolvedBranchId == null || resolvedBranchId <= 0) {
      try {
        prefetchedBranches = await _branchService.fetchBranches();
        if (prefetchedBranches.isNotEmpty) {
          resolvedBranchId = prefetchedBranches.first.id;
          await LocalStorageService.saveSelectedBranchId(resolvedBranchId);
          final existingDefault =
              await LocalStorageService.getUserDefaultBranchId();
          if (existingDefault == null || existingDefault <= 0) {
            await LocalStorageService.saveUserDefaultBranchId(resolvedBranchId);
            await LocalStorageService.saveUserDefaultBranchName(
              prefetchedBranches.first.name,
            );
          }
        }
      } catch (_) {}
    }
    final branchId = resolvedBranchId ?? 1;

    final punchAnywhereFlag =
        await LocalStorageService.getOnlinePunchAnywhere();
    final canPunchAnywhere =
        (user?.canPunchAnywhere ?? false) || punchAnywhereFlag == 1;
    final effectiveHomeBranchId =
        await LocalStorageService.getEffectiveUserBranchId();
    final punchBranchId = (!canPunchAnywhere && effectiveHomeBranchId > 0)
        ? effectiveHomeBranchId
        : branchId;
    final leaveMenuCode = await LocalStorageService.getMenuCodeForModule(
      MenuModuleType.leave,
      fallback: 5105,
    );
    final claimMenuCode = await LocalStorageService.getMenuCodeForModule(
      MenuModuleType.claim,
      fallback: 5121,
    );

    // 2. Fetch all dashboard data concurrently in parallel using Future.wait
    try {
      final results = await Future.wait([
        _employeeService.fetchEmployeeDashboard(date: formattedDate),
        _notificationService.fetchNotificationCount(),
        leaveService.fetchDashboardLeaves(date: formattedDate),
        prefetchedBranches != null
            ? Future.value(prefetchedBranches)
            : _branchService.fetchBranches(),
        _financialYears.isEmpty
            ? _financialYearService.fetchFinancialYears()
            : Future.value(_financialYears),
        _attendanceService.fetchMonthlyAttendanceLogs(date: formattedDate),
        _attendanceService.fetchLastAttendance(
          branchId: punchBranchId,
          employeeId: empId,
        ),
        _attendanceService.fetchHistoryAttendance(
          branchId: punchBranchId,
          employeeId: empId,
        ),
        _menuService.fetchMenus(),
        leaveService.fetchLeaveApplications(),
        _userRightsService.fetchUserRights(
          menuCode: leaveMenuCode,
          branchId: effectiveHomeBranchId,
        ),
        _userRightsService.fetchUserRights(
          menuCode: claimMenuCode,
          branchId: effectiveHomeBranchId,
        ),
      ]);

      if (!mounted) return;

      final employeeDetails = results[0] as EmployeeDetailsModel?;
      final notifCount = results[1] as int;
      final dashboardLeaves = results[2] as List<dynamic>;
      final branches = results[3] as List<BranchModel>;
      final financialYears = results[4] as List<FinancialYearModel>;
      final attendanceLogs = results[5] as List<AttendanceLogModel>;
      var lastAttendance = results[6] as LastAttendanceModel?;
      var historyAttendance = (results.length > 7 && results[7] is List)
          ? results[7] as List<LastAttendanceModel>
          : <LastAttendanceModel>[];
      final menus = (results.length > 8 && results[8] is List<MenuItemModel>)
          ? results[8] as List<MenuItemModel>
          : <MenuItemModel>[];
      final allLeaveApps =
          (results.length > 9 && results[9] is List<LeaveApplicationModel>)
              ? results[9] as List<LeaveApplicationModel>
              : <LeaveApplicationModel>[];
      var leaveRights =
          (results.length > 10 && results[10] is UserRightsModel)
              ? results[10] as UserRightsModel
              : UserRightsModel.noAccess();
      var claimsRights =
          (results.length > 11 && results[11] is UserRightsModel)
              ? results[11] as UserRightsModel
              : UserRightsModel.noAccess();

      // If menus were empty before fetch (e.g. fresh login) and the server
      // returned different menu codes for Leave or Claims, re-check rights.
      final resolvedLeaveMenuCode = await LocalStorageService.getMenuCodeForModule(
        MenuModuleType.leave,
        fallback: leaveMenuCode,
      );
      final resolvedClaimMenuCode = await LocalStorageService.getMenuCodeForModule(
        MenuModuleType.claim,
        fallback: claimMenuCode,
      );
      if (resolvedLeaveMenuCode != leaveMenuCode) {
        leaveRights = await _userRightsService.fetchUserRights(
          menuCode: resolvedLeaveMenuCode,
          branchId: effectiveHomeBranchId,
        );
      }
      if (resolvedClaimMenuCode != claimMenuCode) {
        claimsRights = await _userRightsService.fetchUserRights(
          menuCode: resolvedClaimMenuCode,
          branchId: effectiveHomeBranchId,
        );
      }

      // Determine final selected branch
      BranchModel? finalSelectedBranch = _selectedBranch;
      if (savedBranchId != null && branches.isNotEmpty) {
        finalSelectedBranch = branches.firstWhere(
          (b) => b.value == savedBranchId,
          orElse: () => branches.first,
        );
      } else if (finalSelectedBranch == null && branches.isNotEmpty) {
        finalSelectedBranch = branches.first;
      } else if (finalSelectedBranch != null && branches.isNotEmpty) {
        finalSelectedBranch = branches.firstWhere(
          (b) => b.value == finalSelectedBranch!.value,
          orElse: () => finalSelectedBranch!,
        );
      }

      // If attendance wasn't found for the initial branchId, check the resolved branch
      // (or other assigned branches after fresh login in case the user checked in on another branch)
      if (historyAttendance.isEmpty &&
          (lastAttendance == null || lastAttendance.inOutTime.isEmpty) &&
          empId != null &&
          empId > 0 &&
          branches.isNotEmpty) {
        final candidateBranches = branches
            .where((b) => b.id != branchId)
            .toList();
        for (final candidate in candidateBranches) {
          final altResults = await Future.wait([
            _attendanceService.fetchLastAttendance(
              branchId: candidate.id,
              employeeId: empId,
            ),
            _attendanceService.fetchHistoryAttendance(
              branchId: candidate.id,
              employeeId: empId,
            ),
          ]);
          final altLast = altResults[0] as LastAttendanceModel?;
          final altHistory = altResults[1] as List<LastAttendanceModel>;
          if (altHistory.isNotEmpty ||
              (altLast != null && altLast.inOutTime.isNotEmpty)) {
            lastAttendance = altLast;
            historyAttendance = altHistory;
            if (savedBranchId == null) {
              finalSelectedBranch = candidate;
              await LocalStorageService.saveSelectedBranchId(candidate.id);
            }
            break;
          }
        }
      }

      if (!mounted) return;

      final currentUserName =
          (employeeDetails != null && employeeDetails.name.isNotEmpty)
              ? employeeDetails.name
              : (user?.userName ?? '');

      // Filter only current user's approved leave applications
      final myApprovedLeaves = allLeaveApps.where((app) {
        return _isCurrentUser(app.employee, currentUserName) && app.isApproved;
      }).toList();

      // Filter approved leaves for the current selected month & year
      final myApprovedLeavesThisMonth = myApprovedLeaves.where((app) {
        final leaveDate = _parseLeaveFromDate(app.fromDate);
        return leaveDate != null &&
            leaveDate.year == _selectedDate.year &&
            leaveDate.month == _selectedDate.month;
      }).toList();

      // Calculate days taken for the current selected month only per leave type
      double calculateTakenThisMonth(String leaveName) {
        final target = leaveName.trim().toLowerCase();
        return myApprovedLeavesThisMonth.where((app) {
          final appName = app.leaveName.trim().toLowerCase();
          return appName == target ||
              appName.contains(target) ||
              target.contains(appName);
        }).fold(0.0, (sum, app) => sum + app.noOfLeaves);
      }

      // Calculate dynamic approved leaves for the selected month/year
      final double dynamicLeavesThisMonth = myApprovedLeavesThisMonth.fold(
        0.0,
        (sum, app) => sum + app.noOfLeaves,
      );

      final serverLeaves =
          (employeeDetails?.noOfLeavesForTheMonth ?? 0).toDouble();
      final finalLeavesCount = (dynamicLeavesThisMonth > 0 &&
              (serverLeaves == 0 ||
                  (serverLeaves % 1 == 0 && dynamicLeavesThisMonth % 1 != 0) ||
                  dynamicLeavesThisMonth > serverLeaves))
          ? dynamicLeavesThisMonth
          : (serverLeaves > 0 ? serverLeaves : dynamicLeavesThisMonth);

      final summaryItems = <LeaveSummaryItem>[];
      final distinctColors = [
        const Color(0xFFB06A44), // Warm Bronze
        const Color(0xFF5B9E94), // Sage Teal
        const Color(0xFF1E88E5), // Blue
        const Color(0xFFD97706), // Amber
        const Color(0xFF7C3AED), // Purple
        const Color(0xFFE11D48), // Rose
        const Color(0xFF059669), // Emerald
        const Color(0xFFEA580C), // Orange
      ];
      int colorIdx = 0;

      if (employeeDetails != null && employeeDetails.leaveBalances.isNotEmpty) {
        for (final bal in employeeDetails.leaveBalances) {
          final name = bal.leaveName;
          final color = distinctColors[colorIdx % distinctColors.length];
          colorIdx++;

          final balance =
              (bal.isLossOfPay || bal.closing < 0) ? 0.0 : bal.closing;
          final taken = calculateTakenThisMonth(name);
          final total = bal.isLossOfPay ? 0.0 : (balance + taken);

          summaryItems.add(
            LeaveSummaryItem(
              leaveName: name,
              totalLeaves: total,
              employeesTaken: taken,
              balanceLeaves: balance,
              color: color,
            ),
          );
        }
      } else if (dashboardLeaves.isNotEmpty) {
        for (final item in dashboardLeaves) {
          final name = item['LeaveName']?.toString() ?? 'Leave';
          final lower = name.trim().toLowerCase();
          if (lower.contains('loss of pay') ||
              lower == 'lop' ||
              lower.contains('(lop)') ||
              lower.contains('l.o.p') ||
              lower.contains('lossofpay') ||
              lower.contains('unpaid')) {
            continue;
          }
          final taken = calculateTakenThisMonth(name);
          final total =
              (item['EmployeesTakenLeave'] as num?)?.toDouble() ?? 10.0;
          final opening = total > 0 ? total : 10.0;
          final balance = (opening - taken) >= 0 ? (opening - taken) : 0.0;
          final color = distinctColors[colorIdx % distinctColors.length];
          colorIdx++;

          summaryItems.add(
            LeaveSummaryItem(
              leaveName: name,
              totalLeaves: opening,
              employeesTaken: taken,
              balanceLeaves: balance,
              color: color,
            ),
          );
        }
      }

      setState(() {
        _notificationCount = notifCount;
        _leaveSummaryItems = summaryItems;
        _menuItems = menus;
        _canViewLeave = leaveRights.viewRight;
        _canViewClaims = claimsRights.viewRight;
        _isMenuLoading = false;

        if (employeeDetails != null) {
          _userName = employeeDetails.name;
          _userDesignation = employeeDetails.designation;
          _attendanceCount = employeeDetails.attendanceForTheMonth;
          _leavesCount = finalLeavesCount;
        } else if (user != null && _userName.isEmpty) {
          _userName = user.userName;
        }
        _userAvatarLetter = _userName.isNotEmpty
            ? _userName[0].toUpperCase()
            : 'U';

        _branches = branches;
        _selectedBranch = finalSelectedBranch;

        _financialYears = financialYears;
        if (_selectedFinancialYear == null && _financialYears.isNotEmpty) {
          _selectedFinancialYear = _financialYears.first;
        }

        _liveDayStatus.clear();
        _liveDayDetails.clear();
        int pCount = 0;

        if (attendanceLogs.isNotEmpty) {
          final now = DateTime.now();
          final isCurrentMonth =
              _selectedDate.year == now.year &&
              _selectedDate.month == now.month;

          for (final log in attendanceLogs) {
            final day = log.day;
            final pres = log.present.trim().toUpperCase();
            final inT = log.inTime.trim().toUpperCase();

            if (day > 0) {
              _liveDayDetails[day] = {
                'inTime': log.inTime,
                'outTime': log.outTime,
                'present': log.present,
              };
            }

            final isSunday = pres == 'SUN' || inT == 'SUN';
            final isPresent =
                pres == 'X' ||
                pres == 'P' ||
                pres == 'PR' ||
                pres == 'PRESENT' ||
                (!isSunday &&
                    inT != 'AB' &&
                    inT.isNotEmpty &&
                    inT != '--:--' &&
                    inT != '00:00');
            final isAbsent = pres == 'AB' || pres == 'A' || pres == 'ABSENT';

            if (isSunday) {
              continue;
            } else if (isPresent) {
              if (day > 0) _liveDayStatus[day] = Colors.green;
              pCount++;
            } else if (isAbsent) {
              if (day > 0) _liveDayStatus[day] = Colors.red;
            }
          }

          if (isCurrentMonth) {
            final todayDetails = _liveDayDetails[now.day];
            if (todayDetails != null) {
              final todayIn = todayDetails['inTime'];
              final todayOut = todayDetails['outTime'];

              bool isValidTime(String? time) {
                if (time == null) return false;
                final t = time.trim().toUpperCase();
                if (t.isEmpty ||
                    t == 'AB' ||
                    t == 'A' ||
                    t == 'ABSENT' ||
                    t == 'SUN' ||
                    t == 'SL' ||
                    t == 'CL' ||
                    t == 'PL' ||
                    t == 'HL' ||
                    t == 'WO' ||
                    t == 'OFF' ||
                    t == 'HD' ||
                    t == 'L' ||
                    t == '--:--' ||
                    t == '00:00' ||
                    t == '0:00' ||
                    t == 'NULL') {
                  return false;
                }
                // Must contain digits and a time separator (e.g. 09:30 or 9:30AM)
                return RegExp(r'\d{1,2}[:.]\d{2}').hasMatch(t);
              }

              final hasIn = isValidTime(todayIn);
              final hasOut =
                  isValidTime(todayOut) &&
                  (todayOut?.trim() != todayIn?.trim());

              if (hasIn && !hasOut) {
                _isCheckedIn = true;
                _checkInTime = todayIn!.trim();
                _rawCheckInTime = AttendanceService.formatTo24HourTime(todayIn);
                _checkOutTime = '';
              } else if (hasIn && hasOut) {
                _isCheckedIn = false;
                _checkInTime = todayIn!.trim();
                _rawCheckInTime = AttendanceService.formatTo24HourTime(todayIn);
                _checkOutTime = todayOut!.trim();
              } else {
                _isCheckedIn = false;
              }
            }
          }
        }

        if (employeeDetails != null) {
          _attendanceCount = employeeDetails.attendanceForTheMonth;
          _leavesCount = finalLeavesCount;
        } else {
          _attendanceCount = pCount;
        }

        // Apply first check-in and last check-out from today's history
        _applyAttendanceFromHistory(historyAttendance, lastAttendance);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isMenuLoading = false;
        });
      }
    }
  }

  void _applyAttendanceFromHistory(
    List<LastAttendanceModel> history,
    LastAttendanceModel? lastAttendance,
  ) {
    if (history.isNotEmpty) {
      final inPunches = history.where((p) => p.timeFlag == 0).toList();
      final outPunches = history.where((p) => p.timeFlag == 1).toList();

      // Current checked-in status is determined by the most recent punch overall
      final sortedAll = List<LastAttendanceModel>.from(history)
        ..sort((a, b) {
          final timeA = _parseTimeToSeconds(a.inOutTime);
          final timeB = _parseTimeToSeconds(b.inOutTime);
          if (timeB != timeA) {
            return timeB.compareTo(timeA);
          }
          return b.timeFlag.compareTo(a.timeFlag); // Tie-breaker: flag 1 (OUT) > flag 0 (IN)
        });
      final latestPunch = sortedAll.first;
      _isCheckedIn = latestPunch.isCheckedIn;

      // First check-in = earliest in-punch of today
      if (inPunches.isNotEmpty) {
        inPunches.sort(
          (a, b) => _parseTimeToSeconds(
            a.inOutTime,
          ).compareTo(_parseTimeToSeconds(b.inOutTime)),
        );
        _checkInTime = inPunches.first.formattedTime;
        _rawCheckInTime = inPunches.first.inOutTime;
      }

      // Last check-out = latest out-punch of today
      if (outPunches.isNotEmpty) {
        outPunches.sort(
          (a, b) => _parseTimeToSeconds(
            b.inOutTime,
          ).compareTo(_parseTimeToSeconds(a.inOutTime)),
        );
        _checkOutTime = outPunches.first.formattedTime;
      } else {
        _checkOutTime = '';
      }

      final now = DateTime.now();
      final isCurrentMonth =
          _selectedDate.year == now.year && _selectedDate.month == now.month;
      if (isCurrentMonth) {
        final currentDetails = _liveDayDetails[now.day] ?? {};
        _liveDayDetails[now.day] = {
          'inTime': _checkInTime,
          'outTime': _checkOutTime.isNotEmpty
              ? _checkOutTime
              : (currentDetails['outTime'] ?? '--:--'),
          'present': currentDetails['present'] ?? 'P',
        };
        _liveDayStatus[now.day] = Colors.green;
      }
    } else if (lastAttendance != null && lastAttendance.inOutTime.isNotEmpty) {
      _isCheckedIn = lastAttendance.isCheckedIn;
      if (lastAttendance.isCheckedIn) {
        _checkInTime = lastAttendance.formattedTime;
        _rawCheckInTime = lastAttendance.inOutTime;
      } else {
        _checkOutTime = lastAttendance.formattedTime;
      }
    }
  }

  Future<void> _showTodayPunchHistory() async {
    final currentBranch = _selectedBranch;
    if (currentBranch == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<List<LastAttendanceModel>>(
          future: () async {
            final user = await LocalStorageService.getUser();
            final punchAnywhereFlag =
                await LocalStorageService.getOnlinePunchAnywhere();
            final canPunchAnywhere =
                (user?.canPunchAnywhere ?? false) || punchAnywhereFlag == 1;
            final effectiveHomeBranchId =
                await LocalStorageService.getEffectiveUserBranchId();
            final targetBranchId =
                (!canPunchAnywhere && effectiveHomeBranchId > 0)
                    ? effectiveHomeBranchId
                    : currentBranch.id;

            final serverHistory = await _attendanceService
                .fetchHistoryAttendance(
                  branchId: targetBranchId,
                  employeeId: user?.employeeId,
                );

            serverHistory.sort((a, b) {
              final timeA = _parseTimeToSeconds(a.inOutTime);
              final timeB = _parseTimeToSeconds(b.inOutTime);
              if (timeB != timeA) {
                return timeB.compareTo(
                  timeA,
                ); // Descending (latest punch first)
              }
              return b.timeFlag.compareTo(a.timeFlag);
            });

            // Deduplicate exact duplicate punches (same timestamp & flag)
            // e.g., if a user double-clicks 'Check Out' on the web portal
            final uniqueHistory = <LastAttendanceModel>[];
            for (final punch in serverHistory) {
              final isDuplicate = uniqueHistory.any(
                (existing) =>
                    existing.inOutTime == punch.inOutTime &&
                    existing.timeFlag == punch.timeFlag,
              );
              if (!isDuplicate) {
                uniqueHistory.add(punch);
              }
            }

            return uniqueHistory;
          }(),
          builder: (context, snapshot) {
            final history = snapshot.data ?? [];
            return TodayPunchHistorySheet(
              history: history,
              isLoading: snapshot.connectionState == ConnectionState.waiting,
            );
          },
        );
      },
    );
  }

  static int _parseTimeToSeconds(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPM = clean.contains('PM');
      final isAM = clean.contains('AM');
      final timeOnly = clean.replaceAll(RegExp(r'[^\d:]'), '');
      final parts = timeOnly.split(':');
      if (parts.isNotEmpty) {
        int hours = int.tryParse(parts[0]) ?? 0;
        int minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        int seconds = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
        if (isPM && hours < 12) hours += 12;
        if (isAM && hours == 12) hours = 0;
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (_) {}
    return 0;
  }

  static DateTime? _parseLeaveFromDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return null;
    try {
      final parts = trimmed.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
      return DateTime.tryParse(trimmed);
    } catch (_) {
      return DateTime.tryParse(trimmed);
    }
  }

  static bool _isCurrentUser(String employeeName, String currentUserName) {
    if (currentUserName.trim().isEmpty) return true;
    final empTrim = employeeName.trim();
    if (empTrim.isEmpty || empTrim.toLowerCase() == 'employee') {
      return true;
    }
    final cleanEmp = empTrim.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final cleanUser = currentUserName
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (cleanEmp.isEmpty || cleanUser.isEmpty) return true;
    if (cleanEmp == cleanUser ||
        cleanEmp.contains(cleanUser) ||
        cleanUser.contains(cleanEmp)) {
      return true;
    }
    final userTokens = cleanUser.split(' ').where((t) => t.isNotEmpty);
    final empTokens = cleanEmp.split(' ').where((t) => t.isNotEmpty);
    for (final ut in userTokens) {
      if (empTokens.contains(ut)) return true;
    }
    return false;
  }

  Future<void> _selectDashboardDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadInitialData();
    }
  }

  Future<void> _toggleCheckIn() async {
    debugPrint(
      '======================================================================',
    );
    debugPrint('🔘 [CHECK-IN BUTTON PRESSED]');
    debugPrint(
      '======================================================================',
    );
    debugPrint('[CheckIn] _isLocationChecking: $_isLocationChecking');
    debugPrint('[CheckIn] Current punch state (_isCheckedIn): $_isCheckedIn');
    debugPrint(
      '[CheckIn] Action: ${_isCheckedIn ? "CHECK OUT (Flag 1)" : "CHECK IN (Flag 0)"}',
    );

    if (_isLocationChecking) {
      debugPrint('[CheckIn] Already checking location. Aborting.');
      return;
    }

    setState(() => _isLocationChecking = true);

    try {
      // Refresh branch data from local storage to ensure fresh coordinates
    final user = await LocalStorageService.getUser();
    if ((user?.employeeId ?? 0) <= 0) {
      _showLocationDialog(
        title: 'Employee Profile Not Linked',
        message:
            'Your account does not have an Employee ID linked for mobile attendance.',
        icon: Icons.badge_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final punchAnywhereFlag =
        await LocalStorageService.getOnlinePunchAnywhere();
    final canPunchAnywhere =
        (user?.canPunchAnywhere ?? false) || punchAnywhereFlag == 1;

    debugPrint(
      '[CheckIn] OnlinePunchAnywhere: $punchAnywhereFlag, canPunchAnywhere: $canPunchAnywhere',
    );

    final effectiveHomeBranchId =
        await LocalStorageService.getEffectiveUserBranchId();
    final effectiveHomeBranchName =
        await LocalStorageService.getEffectiveUserBranchName();

    final savedBranchId =
        await LocalStorageService.getSelectedBranchId() ??
        _selectedBranch?.value ??
        1;
    final cachedBranches = await LocalStorageService.getBranches();
    BranchModel? branch;
    if (!canPunchAnywhere && effectiveHomeBranchId > 0) {
      try {
        branch = cachedBranches.firstWhere(
          (b) => b.value == effectiveHomeBranchId,
        );
      } catch (_) {
        branch = BranchModel(
          value: effectiveHomeBranchId,
          name: effectiveHomeBranchName.isNotEmpty
              ? effectiveHomeBranchName
              : 'Home Branch',
        );
      }
      debugPrint(
        '[CheckIn] Locked to Dedicated Home Branch: ${branch.name} (ID: ${branch.id})',
      );
    } else {
      try {
        branch = cachedBranches.firstWhere((b) => b.value == savedBranchId);
      } catch (_) {
        branch = _selectedBranch;
      }

      branch ??= (cachedBranches.isNotEmpty
          ? cachedBranches.first
          : _selectedBranch);

      if (branch != null) {
        _selectedBranch = branch;
      }
    }

    debugPrint('[CheckIn] Saved Branch ID: $savedBranchId');
    debugPrint(
      '[CheckIn] Selected Branch: ${branch?.name} (ID: ${branch?.id}, Value: ${branch?.value})',
    );
    debugPrint(
      '[CheckIn] Branch Coords: Lat: ${branch?.latitude}, Lng: ${branch?.longitude}, Radius: ${branch?.radius}m',
    );

    if (!canPunchAnywhere) {
      if (branch == null ||
          branch.latitude == null ||
          branch.longitude == null ||
          branch.latitude == 0.0 ||
          branch.longitude == 0.0 ||
          branch.radius == null) {
        debugPrint('❌ [CheckIn Error] Branch location is NOT configured!');
        _showLocationDialog(
          title: 'Location Not Configured',
          message: 'Branch location coordinates are not configured.',
          icon: Icons.location_off_rounded,
          iconColor: AppColors.error,
          actionLabel: 'Configure Location',
          onAction: () => BranchLocationSheet.show(context),
        );
        return;
      }
    } else {
      branch ??= BranchModel(
        value: savedBranchId > 0 ? savedBranchId : 1,
        name: 'Online Branch',
        latitude: 0.0,
        longitude: 0.0,
        radius: 0.0,
      );
    }

    Position? position;

    if (!canPunchAnywhere) {
        debugPrint('[CheckIn] Checking if device GPS service is enabled...');
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        debugPrint('[CheckIn] GPS service enabled: $serviceEnabled');
        if (!serviceEnabled) {
          debugPrint(
            '❌ [CheckIn Error] Location services are DISABLED on device',
          );
          if (!mounted) return;
          _showLocationDialog(
            title: 'Location Services Disabled',
            message:
                'Please enable GPS/Location services on your device to verify branch attendance.',
            icon: Icons.location_disabled_rounded,
            iconColor: Colors.orange,
          );
          return;
        }

        debugPrint('[CheckIn] Checking location permission...');
        LocationPermission permission = await Geolocator.checkPermission();
        debugPrint('[CheckIn] Initial location permission: $permission');
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          debugPrint('[CheckIn] Requested permission result: $permission');
          if (permission == LocationPermission.denied) {
            debugPrint('❌ [CheckIn Error] Location permission denied by user');
            if (!mounted) return;
            _showLocationDialog(
              title: 'Permission Denied',
              message:
                  'Location permission is required to verify your branch attendance.',
              icon: Icons.security_rounded,
              iconColor: AppColors.error,
            );
            return;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          debugPrint(
            '❌ [CheckIn Error] Location permission permanently denied',
          );
          if (!mounted) return;
          _showLocationDialog(
            title: 'Permission Permanently Denied',
            message:
                'Location permissions are permanently denied. Please enable them in your device settings to check in or out.',
            icon: Icons.settings_rounded,
            iconColor: AppColors.error,
          );
          return;
        }

        debugPrint('[CheckIn] Acquiring GPS location...');
        try {
          // 1. Allow GPS up to 8s to lock onto satellites during cold app starts
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
        } catch (gpsErr) {
          debugPrint(
            '[CheckIn] Primary GPS lock timed out/failed ($gpsErr). Checking lastKnownPosition...',
          );
          // 2. Only use lastKnownPosition if fresh (< 120s old). Never trust stale locations!
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            final age = DateTime.now()
                .difference(lastKnown.timestamp)
                .inSeconds
                .abs();
            if (age < 120) {
              position = lastKnown;
              debugPrint(
                '[CheckIn] Using fresh lastKnownPosition (age: ${age}s)',
              );
            }
          }

          // 3. If stale or null, retry with low/balanced accuracy for 5 seconds
          if (position == null) {
            try {
              debugPrint('[CheckIn] Retrying with low accuracy for 5s...');
              position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.low,
                  timeLimit: Duration(seconds: 5),
                ),
              );
            } catch (_) {}
          }

          // 4. Last resort fallback
          position ??= lastKnown;
        }

        if (position == null) {
          debugPrint('❌ [CheckIn Error] Unable to acquire device GPS position');
          throw TimeoutException(
            'Unable to acquire current location. Please ensure GPS is enabled and try again.',
          );
        }

        debugPrint(
          '📍 [CheckIn] Device GPS: Lat: ${position.latitude}, Lng: ${position.longitude}, Accuracy: ${position.accuracy}m',
        );
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          branch.latitude!,
          branch.longitude!,
        );

        // Account for realistic mobile device indoor GPS accuracy margin (up to 30m)
        final tolerance = position.accuracy.clamp(0.0, 30.0);
        final effectiveDistance = (distance - tolerance) > 0
            ? (distance - tolerance)
            : 0.0;

        debugPrint(
          '[CheckIn] Distance to branch: ${distance.toStringAsFixed(2)}m',
        );
        debugPrint(
          '[CheckIn] Accuracy tolerance: ${tolerance.toStringAsFixed(2)}m',
        );
        debugPrint(
          '[CheckIn] Effective distance: ${effectiveDistance.toStringAsFixed(2)}m (Allowed radius: ${branch.radius}m)',
        );

        if (effectiveDistance > branch.radius!) {
          debugPrint(
            '❌ [CheckIn Error] Outside branch area! (${distance.toStringAsFixed(0)}m away, radius: ${branch.radius}m)',
          );
          if (!mounted) return;
          _showLocationDialog(
            title: 'Outside Branch Area',
            message: 'You are outside the branch area.',
            icon: Icons.wrong_location_rounded,
            iconColor: AppColors.error,
          );
          return;
        }

        debugPrint(
          '✅ [CheckIn] Geofence check PASSED! Preparing punch data...',
        );
      } else {
        debugPrint(
          '🚀 [CheckIn] OnlinePunchAnywhere is ENABLED (flag = 1). Geofence check bypassed! Capturing GPS coordinates if available...',
        );
        try {
          final isGpsOn = await Geolocator.isLocationServiceEnabled();
          if (isGpsOn) {
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }
            if (permission == LocationPermission.whileInUse ||
                permission == LocationPermission.always) {
              try {
                position = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.medium,
                    timeLimit: Duration(seconds: 5),
                  ),
                );
              } catch (_) {
                position = await Geolocator.getLastKnownPosition();
              }
            }
          }
          if (position != null) {
            debugPrint(
              '📍 [CheckIn Online] Device GPS captured: Lat: ${position.latitude}, Lng: ${position.longitude}',
            );
          } else {
            debugPrint(
              'ℹ️ [CheckIn Online] GPS not available, proceeding without coordinates.',
            );
          }
        } catch (e) {
          debugPrint('ℹ️ [CheckIn Online] Location capture skipped: $e');
        }
      }

      if (!mounted) return;
      final now = DateTime.now();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      final newFlag = _isCheckedIn ? 1 : 0; // 0 = Check In, 1 = Check Out
      final formattedDisplay = LastAttendanceModel(
        inOutTime: timeStr,
        timeFlag: newFlag,
      ).formattedTime;
      final dateFormatted = DateFormat('dd/MM/yyyy').format(now);
      final empId = user!.employeeId;
      final accessPoint = await LocalStorageService.getAccessPoint() ?? '';
      final branchId = branch.id;
      final branchName = branch.name;

      debugPrint('[CheckIn] Access Point: $accessPoint');
      debugPrint(
        '[CheckIn] User: userId=${user.userId}, employeeId=$empId, userName=${user.userName}',
      );
      debugPrint(
        '[CheckIn] Punch Parameters: inOutTime=$timeStr, timeFlag=$newFlag, date=$dateFormatted, branchId=$branchId',
      );

      // 1. Post punch live to server (preserves first inTime on daily attendance Tail, logs every swipe to Tail2)
      final inTimeForTail = _rawCheckInTime.isNotEmpty
          ? _rawCheckInTime
          : timeStr;
      // On Check In (newFlag == 0), OutTime MUST be empty ("") because the employee is checked in, not out!
      final outTimeForTail = newFlag == 1 ? timeStr : '';

      final reason = canPunchAnywhere
          ? (newFlag == 0 ? 'Online Check In' : 'Online Check Out')
          : (newFlag == 0 ? 'Mobile Check In' : 'Mobile Check Out');

      debugPrint(
        '[CheckIn] Calling saveAttendanceWithResult (Lat: ${position?.latitude}, Lng: ${position?.longitude})...',
      );
      final saveResult = await _attendanceService.saveAttendanceWithResult(
        branchId: branchId,
        employeeId: empId,
        inOutTime: timeStr,
        timeFlag: newFlag,
        date: dateFormatted,
        reason: reason,
        inTime: inTimeForTail,
        outTime: outTimeForTail,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      debugPrint(
        '[CheckIn] saveAttendance response: success=${saveResult.success}, error="${saveResult.errorMessage}"',
      );

      if (!saveResult.success) {
        debugPrint('❌ [CheckIn FAILED] Server rejected the punch!');
        if (!mounted) return;
        final cleanMsg =
            saveResult.errorMessage != null &&
                saveResult.errorMessage!.isNotEmpty
            ? (saveResult.errorMessage!.length > 100
                  ? '${saveResult.errorMessage!.substring(0, 97)}...'
                  : saveResult.errorMessage!)
            : "Server error with access point $accessPoint";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attendance punch failed: $cleanMsg'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      debugPrint(
        '✅ [CheckIn SUCCESS] Server accepted punch! Updating local UI...',
      );
      if (!mounted) return;

      setState(() {
        _isCheckedIn = !_isCheckedIn;
        if (_isCheckedIn) {
          // If first check-in of the day, save it. If re-checking in, keep the day's first check-in!
          if (_checkInTime == '--:--' ||
              _checkInTime.isEmpty ||
              _rawCheckInTime.isEmpty) {
            _checkInTime = formattedDisplay;
            _rawCheckInTime = timeStr;
          }
          // Currently checked in, so clear checkout time
          _checkOutTime = '';
          _liveDayDetails[now.day] = {
            'inTime': _checkInTime,
            'outTime': '--:--',
            'present': 'P',
          };
          _liveDayStatus[now.day] = Colors.green;
        } else {
          // Last check-out is updated to this latest check-out
          _checkOutTime = formattedDisplay;
          _liveDayDetails[now.day] = {
            'inTime': _checkInTime,
            'outTime': formattedDisplay,
            'present': 'X',
          };
          _liveDayStatus[now.day] = Colors.green;
        }
      });

      final successText = canPunchAnywhere
          ? (_isCheckedIn
                ? 'Checked in successfully (Online)!'
                : 'Checked out successfully (Online)!')
          : (_isCheckedIn
                ? 'Checked in successfully at $branchName!'
                : 'Checked out successfully at $branchName!');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(successText)),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 2. Fetch latest attendance & monthly logs from server to guarantee sync
      await _loadInitialData();
    } catch (e, stack) {
      debugPrint('❌❌❌ [CheckIn EXCEPTION]: $e');
      debugPrint('[CheckIn StackTrace]: $stack');
      if (!mounted) return;
      _showLocationDialog(
        title: 'Check In Error',
        message:
            'An error occurred while processing your attendance punch.\n\nError: $e',
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
      );
    } finally {
      debugPrint('🔚 [CheckIn] Completed check-in process.');
      if (mounted) {
        setState(() => _isLocationChecking = false);
      }
    }
  }

  void _showLocationDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          if (onAction != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onAction();
              },
              child: Text(
                actionLabel ?? 'Configure Location',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to log out of your session?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await LocalStorageService.clearUserSession();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showHeaderPicker() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _HeaderConfigSheet(
          branches: _branches,
          selectedBranch: _selectedBranch,
          financialYears: _financialYears,
          selectedFinancialYear: _selectedFinancialYear,
          onBranchSelected: (branch) {
            setState(() {
              _selectedBranch = branch;
            });
            LocalStorageService.saveSelectedBranchId(branch.value);
          },
          onFinancialYearSelected: (fy) {
            setState(() {
              _selectedFinancialYear = fy;
            });
          },
          onApply: () {
            Navigator.pop(sheetContext);
            _loadInitialData();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDetails = _liveDayDetails[now.day];
    final serverTodayInTime = todayDetails?['inTime']?.trim() ?? '';
    final serverTodayOutTime = todayDetails?['outTime']?.trim() ?? '';
    final serverTodayPresent = todayDetails?['present']?.trim() ?? '';

    bool isValidClockTime(String? time) {
      if (time == null) return false;
      final t = time.trim();
      if (t.isEmpty ||
          t == '--:--' ||
          t == '00:00' ||
          t == '0:00' ||
          t.toLowerCase() == 'null') {
        return false;
      }
      return RegExp(r'\d{1,2}:\d{2}').hasMatch(t);
    }

    // Only actual clock times (e.g. 09:30 AM, 18:00)
    final validInTime = isValidClockTime(_checkInTime)
        ? _checkInTime
        : (isValidClockTime(serverTodayInTime) ? serverTodayInTime : '');

    final validOutTime = isValidClockTime(_checkOutTime)
        ? _checkOutTime
        : (isValidClockTime(serverTodayOutTime) ? serverTodayOutTime : '');

    // Check for special attendance status (Leave, Absent, Holiday, etc.)
    final rawStatusCode = (serverTodayPresent.isNotEmpty &&
            !isValidClockTime(serverTodayPresent))
        ? serverTodayPresent
        : ((serverTodayInTime.isNotEmpty &&
                !isValidClockTime(serverTodayInTime))
            ? serverTodayInTime
            : ((serverTodayOutTime.isNotEmpty &&
                    !isValidClockTime(serverTodayOutTime))
                ? serverTodayOutTime
                : ''));

    final upperStatus = rawStatusCode.trim().toUpperCase();
    final isLeaveStatus = upperStatus == 'LOP' ||
        upperStatus == 'CL' ||
        upperStatus == 'SL' ||
        upperStatus == 'PL' ||
        upperStatus == 'EL' ||
        upperStatus == 'HD' ||
        upperStatus == 'HL' ||
        upperStatus == 'L' ||
        upperStatus == 'CO';

    final isAbsentStatus = upperStatus == 'AB' ||
        upperStatus == 'A' ||
        upperStatus == 'ABSENT';

    final isWeekendOrHoliday = upperStatus == 'SUN' ||
        upperStatus == 'WO' ||
        upperStatus == 'H' ||
        upperStatus == 'HOLIDAY' ||
        upperStatus == 'OFF';

    String formatSpecialStatus(String code) {
      switch (code) {
        case 'LOP':
          return 'Loss of Pay (LOP)';
        case 'CL':
          return 'Casual Leave (CL)';
        case 'SL':
          return 'Sick Leave (SL)';
        case 'PL':
          return 'Paid Leave (PL)';
        case 'EL':
          return 'Earned Leave (EL)';
        case 'HD':
        case 'HL':
          return 'Half Day Leave';
        case 'CO':
          return 'Comp Off';
        case 'AB':
        case 'A':
        case 'ABSENT':
          return 'Absent';
        case 'SUN':
          return 'Sunday';
        case 'WO':
          return 'Weekly Off';
        case 'H':
        case 'HOLIDAY':
          return 'Holiday';
        case 'OD':
          return 'On Duty';
        default:
          return code;
      }
    }

    final String statusLabel;
    final String statusValue;
    final Color dotColor;

    if (_isCheckedIn) {
      statusLabel = "Today's Check In";
      statusValue = validInTime.isNotEmpty ? validInTime : '--:--';
      dotColor = AppColors.secondary;
    } else if (validOutTime.isNotEmpty) {
      statusLabel = "Today's Check Out";
      statusValue = validOutTime;
      dotColor = Colors.orange;
    } else if (isLeaveStatus) {
      statusLabel = "Today's Status";
      statusValue = formatSpecialStatus(upperStatus);
      dotColor = const Color(0xFFF59E0B);
    } else if (isAbsentStatus) {
      statusLabel = "Today's Status";
      statusValue = "Absent";
      dotColor = AppColors.error;
    } else if (isWeekendOrHoliday) {
      statusLabel = "Today's Status";
      statusValue = formatSpecialStatus(upperStatus);
      dotColor = AppColors.textMuted;
    } else {
      statusLabel = "Today's Check In";
      statusValue = validInTime.isNotEmpty ? validInTime : '--:--';
      dotColor = AppColors.textMuted;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Align(
          alignment: Alignment.centerLeft,
          child: _buildAppBarLogo(context),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 24),
                onPressed: () {
                  LocalStorageService.getAccessPoint().then((ap) async {
                    final user = await LocalStorageService.getUser();
                    debugPrint(
                      '====================================================',
                    );
                    debugPrint('🔔 [NOTIFICATION BELL CLICKED]');
                    debugPrint('🏢 Active AccessPoint: $ap');
                    debugPrint(
                      '👤 Logged-in User: ${user?.userName} (UserID: ${user?.userId}, EmpID: ${user?.employeeId})',
                    );
                    debugPrint(
                      '🔢 Current Notification Count: $_notificationCount',
                    );
                    debugPrint(
                      '====================================================',
                    );
                  });
                  context.push('/notifications').then((_) {
                    if (mounted) _loadInitialData();
                  });
                },
              ),
              if (_notificationCount > 0)
                Positioned(
                  right: 4,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_notificationCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: GestureDetector(
              onTap: () => context.go('/profile'),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text(
                  _userAvatarLetter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Profile & App Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Profile Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _userAvatarLetter,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _userDesignation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _showHeaderPicker();
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.18,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.storefront_rounded,
                                            size: 11.5,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              _selectedBranch != null
                                                  ? '${_selectedBranch!.name}${_selectedFinancialYear != null ? " • ${_selectedFinancialYear!.name}" : ""}'
                                                  : (_branches.isNotEmpty
                                                        ? _branches.first.name
                                                        : 'Select Branch'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          const Icon(
                                            Icons.arrow_drop_down_rounded,
                                            size: 15,
                                            color: AppColors.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),

              // Menu Navigation List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  children: [
                    _buildDrawerTile(
                      icon: Icons.grid_view_rounded,
                      title: 'Home Dashboard',
                      isActive: true,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: AppColors.primary,
                      onTap: () {
                        Navigator.pop(context);
                        context.go('/dashboard');
                      },
                    ),
                    if (_isMenuLoading && _menuItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_menuItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'No modules assigned',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _refreshMenus,
                              icon: const Icon(
                                Icons.refresh_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              tooltip: 'Reload menu',
                            ),
                          ],
                        ),
                      )
                    else
                      ..._menuItems
                          .where((m) {
                            if (m.moduleType ==
                                MenuModuleType.leaveCancellation) {
                              return false;
                            }
                            if (m.moduleType == MenuModuleType.leave &&
                                !_canViewLeave) {
                              return false;
                            }
                            if (m.moduleType == MenuModuleType.claim &&
                                !_canViewClaims) {
                              return false;
                            }
                            return true;
                          })
                          .map(_buildDynamicMenuTile),
                    if (!_menuItems.any(
                      (m) => m.moduleType == MenuModuleType.attendance,
                    ))
                      _buildDrawerTile(
                        icon: Icons.access_time_filled_rounded,
                        title: 'Daily Attendance',
                        isActive: false,
                        iconBg: const Color(0xFFECFDF5),
                        iconColor: const Color(0xFF059669),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/daily-attendance');
                        },
                      ),
                  ],
                ),
              ),

              // Bottom Logout & Version Footer
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _showLogoutConfirmation(context);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFEE2E2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFFDC2626),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sign Out',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                  Text(
                                    'End active session',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: Color(0xFFEF4444),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: !_hasResolvedUser
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Warm Greeting Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Welcome, $_userName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        if (_userDesignation.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            _userDesignation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (_hasLinkedEmployee) ...[
                      const SizedBox(height: 16),

                      // 2. Hero Punch & Today's Attendance Card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.06),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left: Today's In Time Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: dotColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              statusLabel,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          statusValue,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: _showTodayPunchHistory,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2.0,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Text(
                                                  'Tap to view punch history',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                                SizedBox(width: 3),
                                                Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 14,
                                                  color: AppColors.primary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Right: Punch Action Button
                                // Right: Punch Action Button
                                ElevatedButton.icon(
                                  onPressed: _isLocationChecking
                                      ? null
                                      : _toggleCheckIn,
                                  icon: _isLocationChecking
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          _isCheckedIn
                                              ? Icons.logout_rounded
                                              : Icons.login_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    _isLocationChecking
                                        ? 'Verifying...'
                                        : (_isCheckedIn
                                              ? 'Check Out'
                                              : 'Check In'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isCheckedIn
                                        ? AppColors.error
                                        : AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Verification Status Chip - ONLY show when user is checked in
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Overview Header & Date Selector Pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Overview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _selectDashboardDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.cardBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_month_rounded,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat(
                                      'MMM yyyy',
                                    ).format(_selectedDate),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.expand_more_rounded,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 4. Metric Cards Row (Attendance & Leaves Taken)
                      DashboardMetrics(
                        attendanceCount: _attendanceCount,
                        leavesTakenCount: _leavesCount,
                      ),
                      const SizedBox(height: 16),

                      // 5. Attendance Monthly Calendar
                      AttendanceCalendarWidget(
                        liveDayStatus: _liveDayStatus,
                        liveDayDetails: _liveDayDetails,
                        selectedDate: _selectedDate,
                        onDateSelected: (date) {
                          setState(() {
                            _selectedDate = date;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // 6. Leave Balance Overview (Donut Chart / Table View)
                      LeaveBalanceChart(
                        items: _leaveSummaryItems,
                        showApplyLeave: _canViewLeave,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAppBarLogo(BuildContext context) {
    return GestureDetector(
      onTap: () => Scaffold.of(context).openDrawer(),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 26,
            maxWidth: 200,
          ),
          child: Image.asset(
            'assets/images/construct_core_text_logo.png',
            height: 22,
            alignment: Alignment.centerLeft,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Text(
              AppConstants.appName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshMenus() async {
    setState(() => _isMenuLoading = true);
    final menus = await _menuService.fetchMenus();
    final effectiveHomeBranchId =
        await LocalStorageService.getEffectiveUserBranchId();
    final leaveMenuCode = await LocalStorageService.getMenuCodeForModule(
      MenuModuleType.leave,
      fallback: 5105,
    );
    final claimMenuCode = await LocalStorageService.getMenuCodeForModule(
      MenuModuleType.claim,
      fallback: 5121,
    );
    final rightsResults = await Future.wait([
      _userRightsService.fetchUserRights(
        menuCode: leaveMenuCode,
        branchId: effectiveHomeBranchId,
      ),
      _userRightsService.fetchUserRights(
        menuCode: claimMenuCode,
        branchId: effectiveHomeBranchId,
      ),
    ]);
    if (mounted) {
      setState(() {
        _menuItems = menus;
        _canViewLeave = rightsResults[0].viewRight;
        _canViewClaims = rightsResults[1].viewRight;
        _isMenuLoading = false;
      });
    }
  }

  Widget _buildDynamicMenuTile(MenuItemModel item) {
    final IconData icon;
    final Color iconBg;
    final Color iconColor;

    switch (item.moduleType) {
      case MenuModuleType.claim:
        icon = Icons.receipt_long_rounded;
        iconBg = const Color(0xFFEDE9FE);
        iconColor = const Color(0xFF7C3AED);
        break;
      case MenuModuleType.leave:
      case MenuModuleType.leaveCancellation:
        icon = Icons.calendar_today_rounded;
        iconBg = const Color(0xFFFEF3C7);
        iconColor = const Color(0xFFD97706);
        break;
      case MenuModuleType.attendance:
        icon = Icons.access_time_filled_rounded;
        iconBg = const Color(0xFFECFDF5);
        iconColor = const Color(0xFF059669);
        break;
      case MenuModuleType.notifications:
        icon = Icons.notifications_rounded;
        iconBg = const Color(0xFFE0F2FE);
        iconColor = const Color(0xFF0284C7);
        break;
      case MenuModuleType.unknown:
        icon = Icons.construction_rounded;
        iconBg = const Color(0xFFF1F5F9);
        iconColor = const Color(0xFF475569);
        break;
    }

    return _buildDrawerTile(
      icon: icon,
      title: item.name,
      isActive: false,
      iconBg: iconBg,
      iconColor: iconColor,
      onTap: () => _handleDynamicMenuTap(item),
    );
  }

  void _handleDynamicMenuTap(MenuItemModel item) {
    Navigator.pop(context);
    switch (item.moduleType) {
      case MenuModuleType.claim:
        context.push('/claims');
        break;
      case MenuModuleType.leave:
      case MenuModuleType.leaveCancellation:
        context.push('/leave');
        break;
      case MenuModuleType.attendance:
        context.push('/daily-attendance');
        break;
      case MenuModuleType.notifications:
        context.push('/notifications');
        break;
      case MenuModuleType.unknown:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item.name} module is not yet supported on mobile.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required bool isActive,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
    String? badge,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: iconColor.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive
                          ? AppColors.primary
                          : const Color(0xFF334155),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (trailing != null)
                  trailing
                else if (isActive)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFFCBD5E1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderConfigSheet extends StatefulWidget {
  final List<BranchModel> branches;
  final BranchModel? selectedBranch;
  final List<FinancialYearModel> financialYears;
  final FinancialYearModel? selectedFinancialYear;
  final ValueChanged<BranchModel> onBranchSelected;
  final ValueChanged<FinancialYearModel> onFinancialYearSelected;
  final VoidCallback onApply;

  const _HeaderConfigSheet({
    required this.branches,
    required this.selectedBranch,
    required this.financialYears,
    required this.selectedFinancialYear,
    required this.onBranchSelected,
    required this.onFinancialYearSelected,
    required this.onApply,
  });

  @override
  State<_HeaderConfigSheet> createState() => _HeaderConfigSheetState();
}

class _HeaderConfigSheetState extends State<_HeaderConfigSheet> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  BranchModel? _currentBranch;
  FinancialYearModel? _currentFinancialYear;

  @override
  void initState() {
    super.initState();
    _currentBranch = widget.selectedBranch;
    _currentFinancialYear = widget.selectedFinancialYear;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final query = _searchQuery.trim().toLowerCase();
    final filteredBranches = query.isEmpty
        ? widget.branches
        : widget.branches
              .where((b) => b.name.toLowerCase().contains(query))
              .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Office & Financial Year Configuration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Branch Header + Count
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Branch',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (widget.branches.isNotEmpty)
                      Text(
                        '${filteredBranches.length} of ${widget.branches.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Search field for long branch lists
                if (widget.branches.length > 5) ...[
                  TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search branch...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 17,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Scrollable Branch List
                if (widget.branches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No branches available',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                else if (filteredBranches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No matching branches found',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredBranches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final branch = filteredBranches[index];
                        final isSelected =
                            branch.value == _currentBranch?.value;
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() => _currentBranch = branch);
                            widget.onBranchSelected(branch);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.35)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  size: 19,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    branch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 19,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const Divider(height: 20),

                // Financial Year Section (compact horizontal chips so always reachable)
                const Text(
                  'Financial Year',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.financialYears.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No financial years available',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.financialYears.map((fy) {
                      final isSelected =
                          fy.value == _currentFinancialYear?.value;
                      return ChoiceChip(
                        label: Text(fy.name),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _currentFinancialYear = fy);
                          widget.onFinancialYearSelected(fy);
                        },
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        backgroundColor: const Color(0xFFF8FAFC),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : const Color(0xFFE2E8F0),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onApply,
                    child: const Text('Apply Changes'),
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
