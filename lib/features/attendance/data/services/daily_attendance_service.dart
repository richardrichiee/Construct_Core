import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../dashboard/data/services/financial_year_service.dart';
import '../models/daily_attendance_models.dart';

class DailyAttendanceService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<List<CalculationPeriodItem>> fetchCalculationPeriods({
    int? branchId,
    int page = 1,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];

      int effectiveBranchId = branchId ?? 0;
      if (effectiveBranchId <= 0) {
        effectiveBranchId =
            await LocalStorageService.getSelectedBranchId() ?? 0;
      }
      if (effectiveBranchId <= 0) {
        final branches = await LocalStorageService.getBranches();
        if (branches.isNotEmpty) {
          effectiveBranchId = branches.first.value;
        }
      }

      // 1. Primary: Mobile CalculationPeriod API (/api/Construction/Mobile/v1/CalculationPeriod/{accessPoint}/{timeStamp}/{BranchID})
      // Always returns ONLY the periods assigned to this branch.
      // Do NOT fall back to CalculationPeriod/v1/List when this returns an empty list,
      // because an empty list legitimately means no periods are assigned to this branch.
      if (effectiveBranchId > 0) {
        final mobileUrl = AppUrls.getCalculationPeriodUrl(
          accessPoint: accessPoint,
          branchId: effectiveBranchId,
        );
        final res = await _dio.get(
          mobileUrl,
          options: Options(headers: {'Accept': 'application/json'}),
        );
        debugPrint(
          '📋 [CALCULATION PERIODS API RESPONSE] URL: $mobileUrl STATUS: ${res.statusCode} DATA: ${jsonEncode(res.data)}',
        );
        if (res.statusCode == 200 && res.data != null) {
          List rawList = [];
          if (res.data is List) {
            rawList = res.data as List;
          } else if (res.data is Map && res.data['value'] is List) {
            rawList = res.data['value'] as List;
          }
          return rawList
              .whereType<Map>()
              .map(
                (e) => CalculationPeriodItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .where((p) => p.id > 0)
              .toList();
        }
        return [];
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> fetchDatesForPeriod(int calcPeriodId) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];

      // 1. Primary: Mobile CalculationDates API (/api/Construction/Mobile/v1/CalculationDates/{accessPoint}/{timeStamp}/{CalcPeriodID})
      try {
        final mobileUrl = AppUrls.getCalculationDatesUrl(
          accessPoint: accessPoint,
          calcPeriodId: calcPeriodId,
        );
        final res = await _dio.get(
          mobileUrl,
          options: Options(headers: {'Accept': 'application/json'}),
        );
        if (res.statusCode == 200 && res.data != null) {
          List rawList = [];
          if (res.data is List) {
            rawList = res.data as List;
          } else if (res.data is Map && res.data['value'] is List) {
            rawList = res.data['value'] as List;
          }
          final dates = <String>[];
          for (final item in rawList) {
            if (item is String && item.trim().isNotEmpty) {
              dates.add(item.trim());
            } else if (item is Map) {
              final dateStr =
                  (item['CalculationPeriod'] ??
                          item['CalculationDate'] ??
                          item['Date'] ??
                          item['Name'] ??
                          item['Value'])
                      ?.toString();
              if (dateStr != null && dateStr.trim().isNotEmpty) {
                dates.add(dateStr.trim());
              }
            }
          }
          if (dates.isNotEmpty) return dates;
        }
      } catch (_) {}

      // 2. Fallback: DailyAttendance/v1/GetDate
      final url = AppUrls.getDailyAttendanceDatesUrl(
        calcPeriodId: calcPeriodId,
        accessPoint: accessPoint,
      );

      final response = await _dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        List rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data['value'] is List) {
          rawList = data['value'] as List;
        }
        final dates = <String>[];
        for (final item in rawList) {
          if (item is String && item.trim().isNotEmpty) {
            dates.add(item.trim());
          } else if (item is Map) {
            final dateStr =
                (item['CalculationPeriod'] ??
                        item['CalculationDate'] ??
                        item['Date'] ??
                        item['Name'] ??
                        item['Value'])
                    ?.toString();
            if (dateStr != null && dateStr.trim().isNotEmpty) {
              dates.add(dateStr.trim());
            }
          }
        }
        return dates;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<LabourCategoryItem>> fetchLabourCategories({int page = 1}) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];

      final url = AppUrls.getLabourCategoryListUrl(
        page: page,
        accessPoint: accessPoint,
      );

      final response = await _dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null && data['value'] is List) {
          final list = data['value'] as List;
          return list
              .map(
                (e) => LabourCategoryItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<LabourGroupItem>> fetchLabourGroups({int page = 1}) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];

      // 1. Try GeneralData/LabourGroup first (reliable & returns full roster)
      final generalUrl = AppUrls.getLabourGroupGeneralUrl(
        accessPoint: accessPoint,
      );
      try {
        final res = await _dio.get(
          generalUrl,
          options: Options(headers: {'Accept': 'application/json'}),
        );
        if (res.statusCode == 200 && res.data != null) {
          final data = res.data;
          if (data['value'] != null &&
              data['value'] is List &&
              (data['value'] as List).isNotEmpty) {
            final list = data['value'] as List;
            final groups = list
                .whereType<Map>()
                .map(
                  (e) => LabourGroupItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((g) => g.id > 0 && g.name.isNotEmpty)
                .toList();
            if (groups.isNotEmpty) return groups;
          }
        }
      } catch (_) {}

      // 2. Fallback to List/{Page}
      final url = AppUrls.getLabourGroupListUrl(
        page: page,
        accessPoint: accessPoint,
      );

      final response = await _dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null && data['value'] is List) {
          final list = data['value'] as List;
          return list
              .map(
                (e) => LabourGroupItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<DailyAttendanceWorkerItem>> fetchDailyAttendance({
    required int calcPeriodId,
    required int branchId,
    required String date,
    int groupId = 0,
    int categoryId = 0,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];

      final url = AppUrls.getDailyAttendanceGetUrl(accessPoint: accessPoint);

      final payload = {
        'Head': {
          'CalcPeriodID': calcPeriodId.toString(),
          'BranchID': branchId.toString(),
          'date': date,
          'GroupID': groupId.toString(),
          'CategoryID': categoryId.toString(),
        },
      };

      print('================================================================');
      print('🔍 [DAILY ATTENDANCE FETCH REQUEST]');
      print('URL: $url');
      print('PAYLOAD: ${jsonEncode(payload)}');
      print('================================================================');
      debugPrint(
        '🔍 [DAILY ATTENDANCE FETCH REQUEST] URL: $url PAYLOAD: ${jsonEncode(payload)}',
      );

      final response = await _dio.post(
        url,
        data: payload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      print('================================================================');
      print('📦 [DAILY ATTENDANCE FETCH RESPONSE]');
      print('HTTP STATUS: ${response.statusCode}');
      print('RAW RESPONSE DATA: ${jsonEncode(response.data)}');
      print('================================================================');
      debugPrint(
        '📦 [DAILY ATTENDANCE FETCH RESPONSE] STATUS: ${response.statusCode} DATA: ${jsonEncode(response.data)}',
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        List rawList = [];

        if (data is Map) {
          final val = data['value'];
          if (val is Map && val['Tail'] is List) {
            rawList = val['Tail'] as List;
          } else if (val is List) {
            rawList = val;
          } else if (data['Tail'] is List) {
            rawList = data['Tail'] as List;
          }
        } else if (data is List) {
          rawList = data;
        }

        return rawList
            .map(
              (e) => DailyAttendanceWorkerItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<({bool isSuccess, String? errorMessage, dynamic rawResponse})>
  saveDailyAttendance({
    int id = 0,
    required int calcId,
    required int branchId,
    required String date,
    required List<DailyAttendanceWorkerItem> workers,
    int finYearId = 0,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) {
        return (
          isSuccess: false,
          errorMessage: 'Access point missing.',
          rawResponse: null,
        );
      }
      final user = await LocalStorageService.getUser();
      final userId = (user?.userId != null && user!.userId > 0)
          ? user.userId
          : 2;

      // Resolve Financial Year ID dynamically if not explicitly provided
      int effectiveFinYearId = finYearId;
      if (effectiveFinYearId <= 0) {
        try {
          final fyList = await FinancialYearService().fetchFinancialYears();
          if (fyList.isNotEmpty) {
            final dateYear = date.contains('/')
                ? date.split('/').last.trim()
                : '';
            final matched = fyList.firstWhere(
              (fy) => dateYear.isNotEmpty && fy.name.contains(dateYear),
              orElse: () => fyList.first,
            );
            if (matched.value > 0) {
              effectiveFinYearId = matched.value;
            }
          }
        } catch (_) {}
      }
      if (effectiveFinYearId <= 0) effectiveFinYearId = 1;

      final url = AppUrls.getDailyAttendanceSaveUrl(
        id: id,
        calcId: calcId,
        userId: userId,
        branchId: branchId,
        finYearId: effectiveFinYearId,
        accessPoint: accessPoint,
      );

      final payload = {
        'Head': {
          'CalcPeriodID': calcId.toString(),
          'BranchID': branchId.toString(),
          'date': date,
        },
        'Tail': workers.map((w) => w.toTailJson(targetDate: date)).toList(),
      };

      print('================================================================');
      print('🚀 [DAILY ATTENDANCE SAVE REQUEST]');
      print('URL: $url');
      print(
        'PARAMS: id=$id, calcId=$calcId, userId=$userId, branchId=$branchId, finYearId=$effectiveFinYearId, accessPoint=$accessPoint',
      );
      print('HEAD: ${jsonEncode(payload['Head'])}');
      print('WORKERS COUNT: ${workers.length}');
      print('FULL PAYLOAD: ${jsonEncode(payload)}');
      print('================================================================');
      debugPrint('🚀 [DAILY ATTENDANCE SAVE REQUEST] URL: $url');
      debugPrint(
        '🚀 [DAILY ATTENDANCE SAVE REQUEST] PAYLOAD: ${jsonEncode(payload)}',
      );

      final response = await _dio.post(
        url,
        data: payload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      print('================================================================');
      print('📥 [DAILY ATTENDANCE SAVE RESPONSE]');
      print('STATUS CODE: ${response.statusCode}');
      print('RAW RESPONSE DATA: ${jsonEncode(response.data)}');
      print('================================================================');
      debugPrint(
        '📥 [DAILY ATTENDANCE SAVE RESPONSE] STATUS: ${response.statusCode} DATA: ${jsonEncode(response.data)}',
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        if (response.data != null && response.data is Map) {
          final data = response.data as Map;

          // 1. Explicit error object check: e.g. {"value":[], "error":{"Message":"..."}}
          if (data['error'] != null && data['error'] is Map) {
            final err = data['error'] as Map;
            final msg =
                err['Message']?.toString() ?? err['message']?.toString() ?? '';
            if (msg.isNotEmpty) {
              return (
                isSuccess: false,
                errorMessage: msg,
                rawResponse: response.data,
              );
            }
          }
          if (data['ExceptionMessage'] != null &&
              data['ExceptionMessage'].toString().isNotEmpty) {
            return (
              isSuccess: false,
              errorMessage: data['ExceptionMessage'].toString(),
              rawResponse: response.data,
            );
          }

          // 2. Check value array for ERRORMESSAGE
          if (data['value'] != null && data['value'] is List) {
            final valList = data['value'] as List;
            if (valList.isNotEmpty) {
              final first = valList.first;
              if (first is Map) {
                final errorMsg = first['ERRORMESSAGE']?.toString() ?? '';
                if (errorMsg.isNotEmpty) {
                  return (
                    isSuccess: false,
                    errorMessage: errorMsg,
                    rawResponse: response.data,
                  );
                }
              }
              return (
                isSuccess: true,
                errorMessage: null,
                rawResponse: response.data,
              );
            } else {
              return (
                isSuccess: false,
                errorMessage: 'Attendance could not be saved by the server.',
                rawResponse: response.data,
              );
            }
          }
        }
        return (
          isSuccess: true,
          errorMessage: null,
          rawResponse: response.data,
        );
      }

      return (
        isSuccess: false,
        errorMessage: 'Server returned ${response.statusCode}',
        rawResponse: response.data,
      );
    } on DioException catch (dioErr) {
      print('================================================================');
      print('❌ [DAILY ATTENDANCE SAVE DIO ERROR]');
      print('ERROR: $dioErr');
      print('STATUS CODE: ${dioErr.response?.statusCode}');
      print(
        'RESPONSE DATA: ${dioErr.response?.data != null ? jsonEncode(dioErr.response?.data) : "null"}',
      );
      print('================================================================');
      debugPrint('❌ [DAILY ATTENDANCE SAVE DIO ERROR]: $dioErr');

      final respData = dioErr.response?.data;
      if (respData is Map) {
        if (respData['error'] is Map && respData['error']['Message'] != null) {
          return (
            isSuccess: false,
            errorMessage: respData['error']['Message'].toString(),
            rawResponse: respData,
          );
        }
        if (respData['Message'] != null) {
          return (
            isSuccess: false,
            errorMessage: respData['Message'].toString(),
            rawResponse: respData,
          );
        }
        if (respData['ExceptionMessage'] != null) {
          return (
            isSuccess: false,
            errorMessage: respData['ExceptionMessage'].toString(),
            rawResponse: respData,
          );
        }
      }
      return (
        isSuccess: false,
        errorMessage: dioErr.message ?? 'Network error saving attendance.',
        rawResponse: respData,
      );
    } catch (e, stack) {
      print('================================================================');
      print('❌ [DAILY ATTENDANCE SAVE EXCEPTION]');
      print('ERROR: $e');
      print('STACK: $stack');
      print('================================================================');
      debugPrint('❌ [DAILY ATTENDANCE SAVE EXCEPTION]: $e');
      return (isSuccess: false, errorMessage: e.toString(), rawResponse: null);
    }
  }

  Future<({bool isSuccess, String? errorMessage})> deleteDailyAttendance(
    int id,
  ) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) {
        return (isSuccess: false, errorMessage: 'Access point missing.');
      }

      final url = AppUrls.getDailyAttendanceDeleteUrl(
        id: id,
        accessPoint: accessPoint,
      );

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        if (response.data != null && response.data is Map) {
          final data = response.data as Map;
          if (data['value'] != null &&
              data['value'] is List &&
              (data['value'] as List).isNotEmpty) {
            final first = (data['value'] as List).first as Map;
            final errorMsg = first['ERRORMESSAGE']?.toString() ?? '';
            if (errorMsg.isNotEmpty) {
              return (isSuccess: false, errorMessage: errorMsg);
            }
          }
        }
        return (isSuccess: true, errorMessage: null);
      }
      return (
        isSuccess: false,
        errorMessage: 'Server returned ${response.statusCode}',
      );
    } on DioException catch (dioErr) {
      return (
        isSuccess: false,
        errorMessage: dioErr.message ?? 'Network error deleting attendance.',
      );
    } catch (e) {
      return (isSuccess: false, errorMessage: e.toString());
    }
  }
}
