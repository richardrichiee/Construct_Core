class CalculationPeriodItem {
  final int id;
  final String startDate;
  final String endDate;
  final String name;

  const CalculationPeriodItem({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.name = '',
  });

  String get label {
    if (name.isNotEmpty) return name;
    if (startDate.isNotEmpty && endDate.isNotEmpty) {
      return '$startDate - $endDate';
    }
    return startDate.isNotEmpty ? startDate : 'Period #$id';
  }

  factory CalculationPeriodItem.fromJson(Map<String, dynamic> json) {
    final rawName =
        json['Name']?.toString() ?? json['CalculationPeriod']?.toString() ?? '';
    String start =
        json['PeriodStartDate']?.toString() ??
        json['StartDate']?.toString() ??
        '';
    String end =
        json['PeriodEndDate']?.toString() ?? json['EndDate']?.toString() ?? '';

    if ((start.isEmpty || end.isEmpty) && rawName.contains(' - ')) {
      final parts = rawName.split(' - ');
      if (parts.length >= 2) {
        start = parts[0].trim();
        end = parts[1].trim();
      }
    }

    return CalculationPeriodItem(
      id:
          int.tryParse(
            json['Value']?.toString() ??
                json['Key']?.toString() ??
                json['CalcPeriodID']?.toString() ??
                json['ID']?.toString() ??
                '0',
          ) ??
          0,
      startDate: start,
      endDate: end,
      name: rawName,
    );
  }
}

class LabourCategoryItem {
  final int id;
  final String name;

  const LabourCategoryItem({required this.id, required this.name});

  factory LabourCategoryItem.fromJson(Map<String, dynamic> json) {
    return LabourCategoryItem(
      id:
          int.tryParse(
            json['Key']?.toString() ??
                json['Value']?.toString() ??
                json['CategoryID']?.toString() ??
                json['ID']?.toString() ??
                '0',
          ) ??
          0,
      name:
          json['LabourCategoryName']?.toString() ??
          json['CategoryName']?.toString() ??
          json['Name']?.toString() ??
          '',
    );
  }
}

class LabourGroupItem {
  final int id;
  final String name;

  const LabourGroupItem({required this.id, required this.name});

  factory LabourGroupItem.fromJson(Map<String, dynamic> json) {
    return LabourGroupItem(
      id:
          int.tryParse(
            json['Key']?.toString() ??
                json['Value']?.toString() ??
                json['GroupID']?.toString() ??
                json['ID']?.toString() ??
                '0',
          ) ??
          0,
      name:
          json['LabourGroupName']?.toString() ??
          json['GroupName']?.toString() ??
          json['Name']?.toString() ??
          '',
    );
  }
}

class DailyAttendanceWorkerItem {
  final int dailyAttendId;
  final int wageFlag;
  final String employeeId;
  final String employeeName;
  final String labourCode;
  final String category;
  String inTime;
  String inTimeMr;
  String outTime;
  String outTimeMr;
  final String date;

  DailyAttendanceWorkerItem({
    this.dailyAttendId = 0,
    this.wageFlag = 0,
    required this.employeeId,
    required this.employeeName,
    required this.labourCode,
    required this.category,
    required this.inTime,
    this.inTimeMr = 'AM',
    required this.outTime,
    this.outTimeMr = 'PM',
    required this.date,
  });

  bool get isPayrollProcessed => wageFlag != 0;

  static int _parseFlag(dynamic raw) {
    if (raw == null) return 0;
    if (raw is bool) return raw ? 1 : 0;
    final s = raw.toString().trim().toLowerCase();
    if (s == 'true') return 1;
    return int.tryParse(s) ?? 0;
  }

  int? get inTimeMinutes => _toMinutes(inTime, inTimeMr);
  int? get outTimeMinutes => _toMinutes(outTime, outTimeMr);

  String get timeSignature =>
      '${inTime.trim()}|${inTimeMr.trim().toUpperCase()}|${outTime.trim()}|${outTimeMr.trim().toUpperCase()}';

  static int? _toMinutes(String time, String mr) {
    final trimmed = time.trim();
    if (trimmed.isEmpty || !trimmed.contains(':')) return null;
    final parts = trimmed.split(':');
    var h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null || m == null) return null;
    final upperMr = mr.trim().toUpperCase();
    if (upperMr == 'PM' && h < 12) h += 12;
    if (upperMr == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }

  factory DailyAttendanceWorkerItem.fromJson(Map<String, dynamic> json) {
    final rawIn = json['InTime']?.toString() ?? '';
    final rawInMr = json['InTimeMR']?.toString() ?? '';
    final rawOut = json['OutTime']?.toString() ?? '';
    final rawOutMr = json['OutTimeMR']?.toString() ?? '';

    // Split 24-hr time into 12-hr + AM/PM if not provided
    final parsedIn = _normalizeTime(rawIn, rawInMr, defaultPeriod: 'AM');
    final parsedOut = _normalizeTime(rawOut, rawOutMr, defaultPeriod: 'PM');

    final name =
        json['EmployeeName']?.toString() ?? json['Employee']?.toString() ?? '';
    var code =
        json['LabourCode']?.toString() ??
        json['EmployeeCode']?.toString() ??
        '';
    if (code.isEmpty && name.contains(' - ')) {
      final parts = name.split(' - ');
      if (parts.length > 1) {
        code = parts.last.trim();
      }
    }

    return DailyAttendanceWorkerItem(
      dailyAttendId:
          int.tryParse(json['DailyAttendID']?.toString() ?? '0') ?? 0,
      wageFlag: _parseFlag(
        json['WageFlag'] ?? json['wageFlag'] ?? json['Wageflag'],
      ),
      employeeId:
          json['EmployeeID']?.toString() ??
          json['EmployeeId']?.toString() ??
          '0',
      employeeName: name,
      labourCode: code,
      category:
          json['Category']?.toString() ??
          json['LabourCategory']?.toString() ??
          'General',
      inTime: parsedIn.time,
      inTimeMr: parsedIn.period,
      outTime: parsedOut.time,
      outTimeMr: parsedOut.period,
      date: json['Date']?.toString() ?? '',
    );
  }

  static ({String time, String period}) _normalizeTime(
    String rawTime,
    String rawPeriod, {
    required String defaultPeriod,
  }) {
    var trimmed = rawTime.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return (time: '', period: defaultPeriod);
    }

    // Strip date prefix if returned as full timestamp (e.g. 2026-11-01T08:30:00 or 01/11/2026 08:30:00)
    if (trimmed.contains('T')) {
      final parts = trimmed.split('T');
      if (parts.length > 1) {
        trimmed = parts[1].trim();
      }
    } else if (trimmed.contains(' ') &&
        (trimmed.contains('/') || trimmed.contains('-'))) {
      final parts = trimmed.split(' ');
      if (parts.length > 1 && parts[1].contains(':')) {
        trimmed = parts.sublist(1).join(' ').trim();
      }
    }

    var period = rawPeriod.trim().toUpperCase();
    if (period.isEmpty) {
      if (trimmed.toUpperCase().endsWith('AM')) {
        period = 'AM';
        trimmed = trimmed.substring(0, trimmed.length - 2).trim();
      } else if (trimmed.toUpperCase().endsWith('PM')) {
        period = 'PM';
        trimmed = trimmed.substring(0, trimmed.length - 2).trim();
      }
    }

    // Convert 24-hr (e.g. 18:00 or 18:00:00) to 12-hr (06:00 PM) if needed
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      var h = int.tryParse(parts[0]) ?? 0;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      if (period.isEmpty) {
        if (h >= 12) {
          period = 'PM';
          if (h > 12) h -= 12;
        } else {
          period = 'AM';
          if (h == 0) h = 12;
        }
      } else {
        if (h > 12) h -= 12;
        if (h == 0) h = 12;
      }
      final mm = m.toString().padLeft(2, '0');
      final hh = h.toString().padLeft(2, '0');
      return (
        time: '$hh:$mm',
        period: period.isNotEmpty ? period : defaultPeriod,
      );
    }

    return (time: trimmed, period: period.isNotEmpty ? period : defaultPeriod);
  }

  /// Formats time back to 24-hour (or hh:mm) for save payload
  String get formattedInTimeForSave {
    if (inTime.trim().isEmpty) return '';
    return _to24Hour(inTime.trim(), inTimeMr);
  }

  String get formattedOutTimeForSave {
    if (outTime.trim().isEmpty) return '';
    return _to24Hour(outTime.trim(), outTimeMr);
  }

  static String _to24Hour(String time, String mr) {
    if (!time.contains(':')) return time;
    final parts = time.split(':');
    var h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final upperMr = mr.trim().toUpperCase();
    if (upperMr == 'PM' && h < 12) h += 12;
    if (upperMr == 'AM' && h == 12) h = 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Converts a dd/MM/yyyy or yyyy-MM-dd date into ISO yyyy-MM-dd format for backend SQL Server compatibility
  static String formatDateToIso(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(trimmed)) {
      return trimmed.substring(0, 10);
    }
    final parts = trimmed.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      if (parts[0].length == 4) {
        final y = parts[0];
        final m = parts[1].padLeft(2, '0');
        final d = parts[2].padLeft(2, '0');
        return '$y-$m-$d';
      } else if (parts[2].length == 4) {
        final d = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        final y = parts[2];
        return '$y-$m-$d';
      }
    }
    return trimmed;
  }

  Map<String, dynamic> toTailJson({String? targetDate}) {
    final effectiveDate = (targetDate != null && targetDate.isNotEmpty)
        ? targetDate
        : date;
    // Backend DailyAttendanceTail only accepts InTime / OutTime in 24-hr HH:mm format
    // (it ignores InTimeMR / OutTimeMR, so sending 12-hr "06:00" was saved as 06:00 AM).
    final inTime24 = formattedInTimeForSave;
    final outTime24 = formattedOutTimeForSave;
    final isoDate = formatDateToIso(effectiveDate);
    return {
      'EmployeeID': employeeId,
      'EmployeeName': employeeName,
      'InTime': inTime24,
      'Date': isoDate.isNotEmpty ? isoDate : effectiveDate,
      'OutTime': outTime24,
    };
  }
}
