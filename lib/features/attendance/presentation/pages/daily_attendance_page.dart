import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../dashboard/data/models/branch_model.dart';
import '../../../dashboard/data/services/branch_service.dart';
import '../../data/models/daily_attendance_models.dart';
import '../../data/services/daily_attendance_service.dart';

class DailyAttendancePage extends StatefulWidget {
  final DailyAttendanceService? dailyAttendanceService;
  final BranchService? branchService;
  final String? initialBranchStartTime;
  final String? initialBranchEndTime;

  const DailyAttendancePage({
    super.key,
    this.dailyAttendanceService,
    this.branchService,
    this.initialBranchStartTime,
    this.initialBranchEndTime,
  });

  @override
  State<DailyAttendancePage> createState() => _DailyAttendancePageState();
}

class _DailyAttendancePageState extends State<DailyAttendancePage> {
  late final DailyAttendanceService _service;
  late final BranchService _branchService;

  bool _isLoading = true;
  bool _isFetchingWorkers = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  String? _errorMessage;

  String _branchStartTime = '08:00:00';
  String _branchEndTime = '18:00:00';

  BranchModel? _selectedBranch;

  List<CalculationPeriodItem> _calcPeriods = [];
  CalculationPeriodItem? _selectedPeriod;

  List<String> _dates = [];
  String? _selectedDate;

  List<LabourCategoryItem> _categories = [];
  LabourCategoryItem? _selectedCategory;

  List<LabourGroupItem> _groups = [];
  LabourGroupItem? _selectedGroup;

  List<DailyAttendanceWorkerItem> _workers = [];
  Map<String, String> _initialWorkerSignatures = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  DateTime get _todayDateOnly {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _parseDateOnly(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final sep = trimmed.contains('/')
          ? '/'
          : (trimmed.contains('-') ? '-' : null);
      if (sep != null) {
        final parts = trimmed.split(sep);
        if (parts.length >= 3) {
          if (parts[0].length <= 2 && parts[2].length == 4) {
            return DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          } else if (parts[0].length == 4) {
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2].substring(0, 2)),
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isTodayDate(String? dateStr) {
    final dt = _parseDateOnly(dateStr);
    if (dt == null) return false;
    final today = _todayDateOnly;
    return dt.year == today.year &&
        dt.month == today.month &&
        dt.day == today.day;
  }

  bool _isFutureDate(String? dateStr) {
    final dt = _parseDateOnly(dateStr);
    if (dt == null) return false;
    return dt.isAfter(_todayDateOnly);
  }

  bool _isFuturePeriod(CalculationPeriodItem? period) {
    if (period == null) return false;
    final startDt = _parseDateOnly(period.startDate);
    if (startDt != null) {
      return startDt.isAfter(_todayDateOnly);
    }
    if (_dates.isNotEmpty) {
      return _dates.every((d) => _isFutureDate(d));
    }
    return false;
  }

  bool get _isSelectedDateFuture => _isFutureDate(_selectedDate);
  bool get _isSelectedPeriodFuture => _isFuturePeriod(_selectedPeriod);
  bool get _isPayrollProcessed => _workers.any((w) => w.isPayrollProcessed);

  bool get _isCurrentSelectionReadOnly =>
      _isSelectedPeriodFuture || _isSelectedDateFuture || _isPayrollProcessed;

  String? get _readOnlyBannerMessage {
    if (_isSelectedPeriodFuture) {
      return 'Future calculation period — read-only, attendance entry is blocked.';
    }
    if (_isSelectedDateFuture) {
      return 'Future date attendance is blocked — you cannot enter or save attendance for future dates.';
    }
    if (_isPayrollProcessed) {
      return 'Payroll already processed for this period — read-only, editing is blocked.';
    }
    return null;
  }

  bool get _hasSavedAttendance => _workers.any((w) => w.dailyAttendId > 0);

  bool get _hasAnyEntries => _workers.any(
    (w) =>
        w.dailyAttendId > 0 ||
        w.inTime.trim().isNotEmpty ||
        w.outTime.trim().isNotEmpty,
  );

  bool get _canUseQuickFill =>
      _workers.isNotEmpty && !_isCurrentSelectionReadOnly && !_hasAnyEntries;

  bool get _hasUnsavedChanges {
    if (_workers.isEmpty) return false;
    for (final w in _workers) {
      final baseline = _initialWorkerSignatures[w.employeeId];
      if (baseline != null && w.timeSignature != baseline) {
        return true;
      }
    }
    return false;
  }

  void _snapshotWorkerTimes(List<DailyAttendanceWorkerItem> workers) {
    _initialWorkerSignatures = {
      for (final w in workers) w.employeeId: w.timeSignature,
    };
  }

  Future<bool> _confirmDiscardChangesIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved attendance changes. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _handleBackPressed() async {
    final canLeave = await _confirmDiscardChangesIfNeeded();
    if (canLeave && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleRefresh() async {
    final canProceed = await _confirmDiscardChangesIfNeeded();
    if (!canProceed || !mounted) return;
    await _loadInitialLookups(preserveSelection: true);
  }

  @override
  void initState() {
    super.initState();
    _service = widget.dailyAttendanceService ?? DailyAttendanceService();
    _branchService = widget.branchService ?? BranchService();
    if (widget.initialBranchStartTime != null &&
        widget.initialBranchStartTime!.isNotEmpty) {
      _branchStartTime = widget.initialBranchStartTime!;
    }
    if (widget.initialBranchEndTime != null &&
        widget.initialBranchEndTime!.isNotEmpty) {
      _branchEndTime = widget.initialBranchEndTime!;
    }
    _loadInitialLookups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialLookups({bool preserveSelection = false}) async {
    final prevPeriodId = preserveSelection ? _selectedPeriod?.id : null;
    final prevDate = preserveSelection ? _selectedDate : null;

    setState(() {
      if (!preserveSelection) {
        _isLoading = true;
      } else {
        _isFetchingWorkers = true;
      }
      _errorMessage = null;
    });

    try {
      final user = await LocalStorageService.getUser();
      var branchStartTime = _branchStartTime;
      var branchEndTime = _branchEndTime;
      if (user != null) {
        if (widget.initialBranchStartTime == null &&
            user.branchStartTime.isNotEmpty) {
          branchStartTime = user.branchStartTime;
        }
        if (widget.initialBranchEndTime == null &&
            user.branchEndTime.isNotEmpty) {
          branchEndTime = user.branchEndTime;
        }
      }

      final cachedBranches = await LocalStorageService.getBranches();
      // Daily Attendance strictly belongs to the user's dedicated home/default branch from login
      final effectiveBranchId =
          await LocalStorageService.getEffectiveUserBranchId();
      final homeBranchName =
          await LocalStorageService.getEffectiveUserBranchName();

      var branches = cachedBranches;
      if (branches.isEmpty) {
        branches = await _branchService.fetchBranches();
      }

      BranchModel? selectedBranch;
      if (branches.isNotEmpty) {
        if (effectiveBranchId > 0) {
          selectedBranch = branches.firstWhere(
            (b) => b.value == effectiveBranchId,
            orElse: () => branches.first,
          );
        } else {
          selectedBranch = branches.first;
        }
      } else if (effectiveBranchId > 0) {
        selectedBranch = BranchModel(
          value: effectiveBranchId,
          name: homeBranchName.isNotEmpty ? homeBranchName : 'Head Office',
          branchStartTime: branchStartTime,
          branchEndTime: branchEndTime,
        );
      }

      if (widget.initialBranchStartTime == null &&
          selectedBranch?.branchStartTime != null &&
          selectedBranch!.branchStartTime!.isNotEmpty) {
        branchStartTime = selectedBranch.branchStartTime!;
      }
      if (widget.initialBranchEndTime == null &&
          selectedBranch?.branchEndTime != null &&
          selectedBranch!.branchEndTime!.isNotEmpty) {
        branchEndTime = selectedBranch.branchEndTime!;
      }

      final results = await Future.wait([
        _service.fetchCalculationPeriods(branchId: selectedBranch?.value),
        _service.fetchLabourCategories(),
        _service.fetchLabourGroups(),
      ]);

      final periods = results[0] as List<CalculationPeriodItem>;
      final categories = results[1] as List<LabourCategoryItem>;
      final groups = results[2] as List<LabourGroupItem>;

      CalculationPeriodItem? selectedPeriod;
      if (periods.isNotEmpty) {
        if (prevPeriodId != null) {
          selectedPeriod = periods.firstWhere(
            (p) => p.id == prevPeriodId,
            orElse: () => periods.first,
          );
        } else {
          selectedPeriod = periods.first;
        }
      }

      if (!mounted) return;

      setState(() {
        _branchStartTime = branchStartTime;
        _branchEndTime = branchEndTime;
        _selectedBranch = selectedBranch;
        _calcPeriods = periods;
        _selectedPeriod = selectedPeriod;
        _categories = categories;
        _groups = groups;
        if (selectedPeriod == null) {
          _dates = [];
          _selectedDate = null;
          _workers = [];
          _initialWorkerSignatures = {};
          _isFetchingWorkers = false;
        }
        _isLoading = false;
      });

      if (selectedPeriod != null) {
        await _loadDatesForPeriod(selectedPeriod.id, preferredDate: prevDate);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isFetchingWorkers = false;
        _errorMessage = 'Failed to load options: $e';
      });
    }
  }

  Future<void> _loadDatesForPeriod(
    int periodId, {
    String? preferredDate,
  }) async {
    try {
      final dates = await _service.fetchDatesForPeriod(periodId);
      if (!mounted) return;

      String? selectedDate;
      if (dates.isNotEmpty) {
        if (preferredDate != null && dates.contains(preferredDate)) {
          selectedDate = preferredDate;
        } else {
          final todayMatch = dates.where((d) => _isTodayDate(d)).toList();
          if (todayMatch.isNotEmpty) {
            selectedDate = todayMatch.first;
          } else {
            selectedDate = dates.first;
          }
        }
      }

      setState(() {
        _dates = dates;
        _selectedDate = selectedDate;
        if (selectedDate == null) {
          _workers = [];
          _initialWorkerSignatures = {};
          _isFetchingWorkers = false;
        }
      });

      if (selectedDate != null && _selectedBranch != null) {
        await _fetchWorkersForCurrentSelection();
      }
    } catch (_) {}
  }

  Future<void> _fetchWorkersForCurrentSelection() async {
    if (_selectedPeriod == null ||
        _selectedBranch == null ||
        _selectedDate == null) {
      return;
    }

    setState(() {
      _isFetchingWorkers = true;
      _errorMessage = null;
    });

    try {
      final workers = await _service.fetchDailyAttendance(
        calcPeriodId: _selectedPeriod!.id,
        branchId: _selectedBranch!.value,
        date: _selectedDate!,
        groupId: _selectedGroup?.id ?? 0,
        categoryId: _selectedCategory?.id ?? 0,
      );

      if (!mounted) return;

      setState(() {
        _workers = workers;
        _snapshotWorkerTimes(workers);
        _isFetchingWorkers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingWorkers = false;
        _errorMessage = 'Unable to fetch workers for selected date: $e';
      });
    }
  }

  List<DailyAttendanceWorkerItem> get _filteredWorkers {
    if (_searchQuery.trim().isEmpty) return _workers;
    final query = _searchQuery.trim().toLowerCase();
    return _workers.where((w) {
      return w.employeeName.toLowerCase().contains(query) ||
          w.labourCode.toLowerCase().contains(query) ||
          w.category.toLowerCase().contains(query);
    }).toList();
  }

  void _showValidationError(String message) {
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_selectedPeriod == null ||
        _selectedBranch == null ||
        _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Calculation Period, Branch and Date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isCurrentSelectionReadOnly) {
      _showValidationError(
        _readOnlyBannerMessage ?? 'Editing is blocked for this selection.',
      );
      return;
    }

    if (!_hasUnsavedChanges) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to save.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate every worker's In/Out times:
    // - In Time alone (without Out Time) is allowed
    // - Out Time alone (without In Time) is rejected
    // - When both are entered, Out Time must be strictly after In Time
    for (final w in _workers) {
      final hasIn = w.inTime.trim().isNotEmpty;
      final hasOut = w.outTime.trim().isNotEmpty;

      if (!hasIn && hasOut) {
        _showValidationError(
          'Please enter In Time for ${w.employeeName} (Out Time cannot be saved without In Time).',
        );
        return;
      }
      if (hasIn && hasOut) {
        final inMins = w.inTimeMinutes;
        final outMins = w.outTimeMinutes;
        if (inMins != null && outMins != null && outMins <= inMins) {
          _showValidationError(
            outMins == inMins
                ? 'Out time cannot be equal to In time (${w.employeeName}). Out time must be after In time.'
                : 'Out time must be after In time (${w.employeeName}).',
          );
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final firstId = _workers.isNotEmpty ? _workers.first.dailyAttendId : 0;

    debugPrint(
      '💾 [DailyAttendancePage] Saving ${_workers.length} workers for date: $_selectedDate, period: ${_selectedPeriod?.id}, branch: ${_selectedBranch?.value}...',
    );
    final result = await _service.saveDailyAttendance(
      id: firstId,
      calcId: _selectedPeriod!.id,
      branchId: _selectedBranch!.value,
      date: _selectedDate!,
      workers: _workers,
    );

    debugPrint(
      '💾 [DailyAttendancePage] Save result: isSuccess=${result.isSuccess}, errorMessage=${result.errorMessage}, rawResponse=${jsonEncode(result.rawResponse)}',
    );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result.isSuccess) {
      setState(() => _errorMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Daily Attendance saved successfully!')),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Re-fetch directly from server to verify and display the persisted data
      await _fetchWorkersForCurrentSelection();
    } else {
      final error = result.errorMessage ?? 'Failed to save attendance.';
      setState(() {
        _errorMessage = error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $error'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    if (_isCurrentSelectionReadOnly) {
      _showValidationError(
        _readOnlyBannerMessage ?? 'Deleting is blocked for this selection.',
      );
      return;
    }

    final firstId = _workers.isNotEmpty ? _workers.first.dailyAttendId : 0;
    if (firstId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No existing saved attendance found to delete for this date.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Daily Attendance'),
        content: Text(
          'Are you sure you want to delete daily attendance for ${_selectedDate ?? "this date"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    final res = await _service.deleteDailyAttendance(firstId);

    if (!mounted) return;

    setState(() => _isDeleting = false);

    if (res.isSuccess) {
      setState(() {
        _errorMessage = null;
        for (final w in _workers) {
          w.inTime = '';
          w.outTime = '';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Daily Attendance deleted successfully.')),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchWorkersForCurrentSelection();
    } else {
      setState(() {
        _errorMessage = res.errorMessage ?? 'Failed to delete attendance.';
      });
    }
  }

  Future<void> _pickTimeForWorker(
    DailyAttendanceWorkerItem worker,
    bool isInTime,
  ) async {
    if (_isCurrentSelectionReadOnly) {
      _showValidationError(
        _readOnlyBannerMessage ?? 'Editing is blocked for this selection.',
      );
      return;
    }

    final currentStr = isInTime ? worker.inTime : worker.outTime;
    final currentMr = isInTime ? worker.inTimeMr : worker.outTimeMr;

    var initialHour = 8;
    var initialMinute = 0;
    if (currentStr.contains(':')) {
      final parts = currentStr.split(':');
      var h = int.tryParse(parts[0]) ?? 8;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      if (currentMr.toUpperCase() == 'PM' && h < 12) h += 12;
      if (currentMr.toUpperCase() == 'AM' && h == 12) h = 0;
      initialHour = h;
      initialMinute = m;
    } else if (!isInTime) {
      initialHour = 18;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked == null || !mounted) return;

    final hourOfPeriod = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    final formattedTime =
        '${hourOfPeriod.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final period = picked.period == DayPeriod.am ? 'AM' : 'PM';

    setState(() {
      if (isInTime) {
        worker.inTime = formattedTime;
        worker.inTimeMr = period;
      } else {
        worker.outTime = formattedTime;
        worker.outTimeMr = period;
      }
    });
  }

  ({String formatted12Hr, String period, String label}) _parseBranchTimeInfo(
    String raw, {
    required int fallbackHour24,
    required int fallbackMinute,
    required String fallbackPeriod,
    required String fallbackLabel,
  }) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      final hh =
          (fallbackHour24 > 12
                  ? fallbackHour24 - 12
                  : (fallbackHour24 == 0 ? 12 : fallbackHour24))
              .toString()
              .padLeft(2, '0');
      final mm = fallbackMinute.toString().padLeft(2, '0');
      return (
        formatted12Hr: '$hh:$mm',
        period: fallbackPeriod,
        label: fallbackLabel,
      );
    }

    String? explicitPeriod;
    if (trimmed.toUpperCase().endsWith('AM')) {
      explicitPeriod = 'AM';
      trimmed = trimmed.substring(0, trimmed.length - 2).trim();
    } else if (trimmed.toUpperCase().endsWith('PM')) {
      explicitPeriod = 'PM';
      trimmed = trimmed.substring(0, trimmed.length - 2).trim();
    }

    int? hour;
    int minute = 0;

    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      hour = int.tryParse(parts[0]);
      if (parts.length > 1) {
        final minPart = parts[1].split('.')[0];
        minute = int.tryParse(minPart) ?? 0;
      }
    } else {
      hour = int.tryParse(trimmed);
    }

    if (hour == null) {
      final hh =
          (fallbackHour24 > 12
                  ? fallbackHour24 - 12
                  : (fallbackHour24 == 0 ? 12 : fallbackHour24))
              .toString()
              .padLeft(2, '0');
      final mm = fallbackMinute.toString().padLeft(2, '0');
      return (
        formatted12Hr: '$hh:$mm',
        period: fallbackPeriod,
        label: fallbackLabel,
      );
    }

    String period;
    int hour12;

    if (explicitPeriod != null) {
      period = explicitPeriod;
      hour12 = hour;
      if (hour12 > 12) hour12 -= 12;
      if (hour12 == 0) hour12 = 12;
    } else {
      if (hour >= 12) {
        period = 'PM';
        hour12 = hour > 12 ? hour - 12 : 12;
      } else {
        period = 'AM';
        hour12 = hour == 0 ? 12 : hour;
      }
    }

    final formatted12Hr =
        '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final label = minute == 0
        ? '$hour12 $period'
        : '$hour12:${minute.toString().padLeft(2, '0')} $period';

    return (formatted12Hr: formatted12Hr, period: period, label: label);
  }

  void _applyStandardTimesToAll() {
    if (!_canUseQuickFill) return;
    final startInfo = _parseBranchTimeInfo(
      _branchStartTime,
      fallbackHour24: 8,
      fallbackMinute: 0,
      fallbackPeriod: 'AM',
      fallbackLabel: '8 AM',
    );
    final endInfo = _parseBranchTimeInfo(
      _branchEndTime,
      fallbackHour24: 18,
      fallbackMinute: 0,
      fallbackPeriod: 'PM',
      fallbackLabel: '6 PM',
    );

    setState(() {
      for (final w in _workers) {
        if (w.inTime.isEmpty) {
          w.inTime = startInfo.formatted12Hr;
          w.inTimeMr = startInfo.period;
        }
        if (w.outTime.isEmpty) {
          w.outTime = endInfo.formatted12Hr;
          w.outTimeMr = endInfo.period;
        }
      }
    });
  }

  ({String dayNumber, String weekday, String fullDate}) _parseDateInfo(
    String dateStr,
  ) {
    final trimmed = dateStr.trim();
    if (trimmed.isEmpty) return (dayNumber: '', weekday: '', fullDate: '');
    try {
      if (trimmed.contains('/') || trimmed.contains('-')) {
        final sep = trimmed.contains('/') ? '/' : '-';
        final parts = trimmed.split(sep);
        if (parts.length >= 3) {
          if (parts[0].length <= 2 && parts[2].length == 4) {
            // dd/MM/yyyy
            final day = int.parse(parts[0]);
            final month = int.parse(parts[1]);
            final year = int.parse(parts[2]);
            final dt = DateTime(year, month, day);
            const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return (
              dayNumber: parts[0].padLeft(2, '0'),
              weekday: weekdays[dt.weekday - 1],
              fullDate: trimmed,
            );
          } else if (parts[0].length == 4) {
            // yyyy/MM/dd
            final year = int.parse(parts[0]);
            final month = int.parse(parts[1]);
            final day = int.parse(parts[2]);
            final dt = DateTime(year, month, day);
            const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return (
              dayNumber: parts[2].padLeft(2, '0'),
              weekday: weekdays[dt.weekday - 1],
              fullDate: trimmed,
            );
          }
        }
      }
    } catch (_) {}
    final parts = trimmed.split(RegExp(r'[/ -]'));
    final dayOnly = parts.isNotEmpty && parts.first.length <= 2
        ? parts.first.padLeft(2, '0')
        : trimmed;
    return (dayNumber: dayOnly, weekday: '', fullDate: trimmed);
  }

  void _openFilterBottomSheet() {
    LabourGroupItem? tempGroup = _selectedGroup;
    LabourCategoryItem? tempCategory = _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter Workers',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (tempGroup != null || tempCategory != null)
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                tempGroup = null;
                                tempCategory = null;
                              });
                            },
                            child: Text(
                              'Reset All',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LABOUR GROUP',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LabourGroupItem?>(
                          value: tempGroup,
                          isExpanded: true,
                          hint: const Text(
                            'All Groups',
                            style: TextStyle(fontSize: 13),
                          ),
                          items: [
                            const DropdownMenuItem<LabourGroupItem?>(
                              value: null,
                              child: Text(
                                'All Groups',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            ..._groups.map((g) {
                              return DropdownMenuItem<LabourGroupItem?>(
                                value: g,
                                child: Text(
                                  g.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }),
                          ],
                          onChanged: (g) {
                            setSheetState(() => tempGroup = g);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LABOUR CATEGORY',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LabourCategoryItem?>(
                          value: tempCategory,
                          isExpanded: true,
                          hint: const Text(
                            'All Categories',
                            style: TextStyle(fontSize: 13),
                          ),
                          items: [
                            const DropdownMenuItem<LabourCategoryItem?>(
                              value: null,
                              child: Text(
                                'All Categories',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            ..._categories.map((c) {
                              return DropdownMenuItem<LabourCategoryItem?>(
                                value: c,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }),
                          ],
                          onChanged: (c) {
                            setSheetState(() => tempCategory = c);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          setState(() {
                            _selectedGroup = tempGroup;
                            _selectedCategory = tempCategory;
                          });
                          _fetchWorkersForCurrentSelection();
                        },
                        child: Text(
                          'Apply Filters',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnlyMsg = _readOnlyBannerMessage;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscardChangesIfNeeded();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Daily Attendance',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF0F172A),
                ),
              ),
              if (_selectedBranch != null && _selectedBranch!.name.isNotEmpty)
                Text(
                  _selectedBranch!.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: _handleBackPressed,
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _isLoading || _isFetchingWorkers
                  ? null
                  : _handleRefresh,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: const Color(0xFFE2E8F0), height: 1),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Top Filter & Selection Header Card
                  _buildTopFilterHeader(),

                  // Read-Only Banner (Future Period / Future Date / Payroll Processed)
                  if (readOnlyMsg != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              readOnlyMsg,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: const Color(0xFF92400E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Error Banner if any
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                color: const Color(0xFFB91C1C),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Workers Count & Quick Action bar
                  _buildActionBarHeader(),

                  // Labour List with Pull-to-Refresh
                  Expanded(
                    child: _isFetchingWorkers
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _handleRefresh,
                            child: _filteredWorkers.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      SizedBox(
                                        height: 260,
                                        child: _buildEmptyState(),
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      20,
                                    ),
                                    itemCount: _filteredWorkers.length,
                                    itemBuilder: (context, index) {
                                      final worker = _filteredWorkers[index];
                                      return _buildWorkerCard(worker, index);
                                    },
                                  ),
                          ),
                  ),
                ],
              ),
        bottomNavigationBar: _buildBottomSaveBar(),
      ),
    );
  }

  Widget _buildTopFilterHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Calculation Period (Full Width)
          _buildCalculationPeriodSection(),
          const SizedBox(height: 12),

          // 2. Calculation Dates (Compact Day Pills)
          if (_dates.isNotEmpty) ...[
            _buildCalculationDatesSection(),
            const SizedBox(height: 12),
          ],

          // 3. Search & Filter Bar
          _buildSearchAndFilterBar(),
        ],
      ),
    );
  }

  Widget _buildCalculationPeriodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.date_range_rounded,
              size: 13,
              color: Color(0xFF475569),
            ),
            const SizedBox(width: 5),
            Text(
              'CALCULATION PERIOD',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CalculationPeriodItem>(
              value: _selectedPeriod,
              isExpanded: true,
              hint: Text(
                _calcPeriods.isEmpty
                    ? 'No calculation periods'
                    : 'Select Calculation Period',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF64748B),
              ),
              items: _calcPeriods.map((p) {
                final isFuture = _isFuturePeriod(p);
                return DropdownMenuItem<CalculationPeriodItem>(
                  value: p,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isFuture
                                ? const Color(0xFF64748B)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (isFuture) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: Text(
                            'Future',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: (p) async {
                if (p != null && p != _selectedPeriod) {
                  final canSwitch = await _confirmDiscardChangesIfNeeded();
                  if (!canSwitch || !mounted) return;
                  setState(() => _selectedPeriod = p);
                  _loadDatesForPeriod(p.id);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalculationDatesSection() {
    final selectedIsToday = _isTodayDate(_selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 5),
                Text(
                  'CALCULATION DATES',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            if (_selectedDate != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedIsToday) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF6EE7B7)),
                      ),
                      child: Text(
                        'TODAY',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF047857),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _selectedDate!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = _dates.length;
            const gap = 6.0;
            final fitAll = count > 0 && count <= 7;
            final pillWidth = fitAll
                ? ((constraints.maxWidth - (count - 1) * gap) / count).clamp(
                    38.0,
                    56.0,
                  )
                : 50.0;

            Widget buildPill(String d) {
              final isSelected = d == _selectedDate;
              final isToday = _isTodayDate(d);
              final isFuture = _isFutureDate(d);
              final parsed = _parseDateInfo(d);

              return InkWell(
                onTap: () async {
                  if (_selectedDate != d) {
                    final canSwitch = await _confirmDiscardChangesIfNeeded();
                    if (!canSwitch || !mounted) return;
                    setState(() => _selectedDate = d);
                    _fetchWorkersForCurrentSelection();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: pillWidth,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? (isFuture
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF64748B),
                                    Color(0xFF475569),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF081735),
                                    Color(0xFF1C64F2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ))
                        : null,
                    color: isSelected
                        ? null
                        : (isToday
                              ? const Color(0xFFECFDF5)
                              : (isFuture
                                    ? const Color(0xFFF8FAFC)
                                    : const Color(0xFFF1F5F9))),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? (isToday
                                ? const Color(0xFF34D399)
                                : Colors.transparent)
                          : (isToday
                                ? const Color(0xFF059669)
                                : const Color(0xFFE2E8F0)),
                      width: (isToday || isSelected) ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  (isFuture
                                          ? const Color(0xFF475569)
                                          : const Color(0xFF1C64F2))
                                      .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (parsed.weekday.isNotEmpty)
                        Text(
                          parsed.weekday.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: (isSelected || isToday)
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.88)
                                : (isToday
                                      ? const Color(0xFF047857)
                                      : (isFuture
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B))),
                            letterSpacing: 0.2,
                          ),
                        ),
                      Text(
                        parsed.dayNumber,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                    ? const Color(0xFF065F46)
                                    : (isFuture
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF1E293B))),
                        ),
                      ),
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF34D399)
                                : const Color(0xFF059669),
                            shape: BoxShape.circle,
                          ),
                        )
                      else if (isFuture)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 9,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.8)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            if (fitAll) {
              return SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int i = 0; i < _dates.length; i++)
                      buildPill(_dates[i]),
                  ],
                ),
              );
            }

            return SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _dates.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: gap),
                itemBuilder: (context, i) => buildPill(_dates[i]),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
    final hasActiveFilters =
        _selectedGroup != null || _selectedCategory != null;
    final activeCount =
        (_selectedGroup != null ? 1 : 0) + (_selectedCategory != null ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search employee / code...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _openFilterBottomSheet,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hasActiveFilters
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasActiveFilters
                        ? AppColors.primary
                        : const Color(0xFFCBD5E1),
                    width: hasActiveFilters ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 17,
                      color: hasActiveFilters
                          ? AppColors.primary
                          : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Filter',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasActiveFilters
                            ? AppColors.primary
                            : const Color(0xFF475569),
                      ),
                    ),
                    if (hasActiveFilters) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$activeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (hasActiveFilters) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (_selectedGroup != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      label: Text(
                        'Group: ${_selectedGroup!.name}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      deleteIconColor: AppColors.primary,
                      onDeleted: () {
                        setState(() => _selectedGroup = null);
                        _fetchWorkersForCurrentSelection();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                    ),
                  ),
                if (_selectedCategory != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      label: Text(
                        'Category: ${_selectedCategory!.name}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      deleteIconColor: AppColors.primary,
                      onDeleted: () {
                        setState(() => _selectedCategory = null);
                        _fetchWorkersForCurrentSelection();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedGroup = null;
                      _selectedCategory = null;
                    });
                    _fetchWorkersForCurrentSelection();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear all',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionBarHeader() {
    final startInfo = _parseBranchTimeInfo(
      _branchStartTime,
      fallbackHour24: 8,
      fallbackMinute: 0,
      fallbackPeriod: 'AM',
      fallbackLabel: '8 AM',
    );
    final endInfo = _parseBranchTimeInfo(
      _branchEndTime,
      fallbackHour24: 18,
      fallbackMinute: 0,
      fallbackPeriod: 'PM',
      fallbackLabel: '6 PM',
    );
    final fillButtonText = 'Fill ${startInfo.label} - ${endInfo.label}';
    final canFill = _canUseQuickFill;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_filteredWorkers.length} Workers',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF475569),
            ),
          ),
          ElevatedButton.icon(
            onPressed: canFill ? _applyStandardTimesToAll : null,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
            label: Text(
              fillButtonText,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              elevation: 0,
              backgroundColor: const Color(0xFF1C64F2),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(DailyAttendanceWorkerItem worker, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category Pill + Employee Code + Name
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  worker.category.isNotEmpty ? worker.category : 'General',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (worker.labourCode.isNotEmpty) ...[
                Text(
                  '#${worker.labourCode}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  worker.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // In Time & Out Time Pickers
          Row(
            children: [
              // In Time Box
              Expanded(
                child: _buildTimeInputBox(
                  label: 'In Time',
                  time: worker.inTime,
                  period: worker.inTimeMr,
                  color: const Color(0xFF059669),
                  readOnly: _isCurrentSelectionReadOnly,
                  onTap: () => _pickTimeForWorker(worker, true),
                  onTogglePeriod: () {
                    if (_isCurrentSelectionReadOnly) return;
                    setState(() {
                      worker.inTimeMr = worker.inTimeMr == 'AM' ? 'PM' : 'AM';
                    });
                  },
                  onClear: () {
                    if (_isCurrentSelectionReadOnly) return;
                    setState(() {
                      worker.inTime = '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Out Time Box
              Expanded(
                child: _buildTimeInputBox(
                  label: 'Out Time',
                  time: worker.outTime,
                  period: worker.outTimeMr,
                  color: const Color(0xFFDC2626),
                  readOnly: _isCurrentSelectionReadOnly,
                  onTap: () => _pickTimeForWorker(worker, false),
                  onTogglePeriod: () {
                    if (_isCurrentSelectionReadOnly) return;
                    setState(() {
                      worker.outTimeMr = worker.outTimeMr == 'PM' ? 'AM' : 'PM';
                    });
                  },
                  onClear: () {
                    if (_isCurrentSelectionReadOnly) return;
                    setState(() {
                      worker.outTime = '';
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInputBox({
    required String label,
    required String time,
    required String period,
    required Color color,
    required VoidCallback onTap,
    required VoidCallback onTogglePeriod,
    required VoidCallback onClear,
    bool readOnly = false,
  }) {
    final hasTime = time.isNotEmpty;

    return Opacity(
      opacity: readOnly ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasTime
              ? color.withValues(alpha: 0.05)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasTime
                ? color.withValues(alpha: 0.3)
                : const Color(0xFFCBD5E1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                if (hasTime && !readOnly)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: readOnly ? null : onTap,
                    child: Text(
                      hasTime ? time : '--:--',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: hasTime
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: readOnly ? null : onTogglePeriod,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: hasTime
                          ? color.withValues(alpha: 0.15)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      period,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: hasTime ? color : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final noPeriods = _calcPeriods.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                noPeriods
                    ? Icons.date_range_rounded
                    : Icons.people_outline_rounded,
                size: 32,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              noPeriods ? 'No Calculation Periods' : 'No Workers Found',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              noPeriods
                  ? 'No calculation periods are currently assigned for this branch.'
                  : 'No labour records for ${_selectedDate ?? "this selection"}. Try another date or filter.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSaveBar() {
    final paddingBottom = MediaQuery.paddingOf(context).bottom;
    final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomInset = paddingBottom > 0 ? paddingBottom : viewPaddingBottom;

    final canDelete =
        !_isSaving &&
        !_isDeleting &&
        !_isCurrentSelectionReadOnly &&
        _hasSavedAttendance;
    final canSave =
        !_isSaving &&
        !_isDeleting &&
        !_isCurrentSelectionReadOnly &&
        _workers.isNotEmpty &&
        _hasUnsavedChanges;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Delete button
          OutlinedButton(
            onPressed: canDelete ? _handleDelete : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              disabledForegroundColor: const Color(0xFFCBD5E1),
              side: BorderSide(
                color: canDelete
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFE2E8F0),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 20),
          ),
          const SizedBox(width: 12),

          // Save button
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: canSave || _isSaving
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF081735),
                          Color(0xFF1342A0),
                          Color(0xFF1C64F2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: canSave || _isSaving ? null : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(12),
                boxShadow: canSave || _isSaving
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF1C64F2,
                          ).withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canSave ? _handleSave : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Saving...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isCurrentSelectionReadOnly
                                    ? Icons.lock_outline_rounded
                                    : Icons.save_rounded,
                                size: 18,
                                color: canSave
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isCurrentSelectionReadOnly
                                    ? 'Read Only'
                                    : 'Save Attendance',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: canSave
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
