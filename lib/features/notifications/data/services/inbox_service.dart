import 'package:dio/dio.dart';
import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';

class InboxService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// GET /api/Construction/Mobile/v1/InboxCount/{accessPoint}/{timeStamp}/{UserID}
  Future<int> fetchInboxCount() async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return 0;
      final user = await LocalStorageService.getUser();
      if (user == null || user.userId <= 0) return 0;

      final url = AppUrls.getInboxCountUrl(
        accessPoint: accessPoint,
        userId: user.userId,
      );

      final response = await _dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final value = response.data['value'];
        if (value is List && value.isNotEmpty && value.first is Map) {
          final first = value.first as Map;
          final cntRaw =
              first['Cnt'] ?? first['cnt'] ?? first['Count'] ?? first['count'];
          final parsed = int.tryParse(cntRaw?.toString() ?? '');
          if (parsed != null) return parsed;
        }
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// GET /api/Construction/Mobile/v1/InboxData/{accessPoint}/{timeStamp}/{UserID}
  Future<List<Map<String, dynamic>>> fetchInboxSummary() async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];
      final user = await LocalStorageService.getUser();
      final userId = user?.userId ?? 2;

      // Primary: Mobile InboxData endpoint
      try {
        final mobileUrl = AppUrls.getInboxDataUrl(
          accessPoint: accessPoint,
          userId: userId,
        );

        final response = await _dio.get(
          mobileUrl,
          options: Options(headers: {'Accept': 'application/json'}),
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data['value'] != null && data['value'] is List) {
            final list = data['value'] as List;
            return list
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          }
        }
      } catch (e) {
        // Fallback to legacy endpoint if mobile endpoint fails
      }

      // Fallback: POST /api/Construction/General/v1/Inbox/{timeStamp}/{accessPoint}
      final url = AppUrls.getInboxUrl(accessPoint: accessPoint);
      final payload = {
        "Head": {"UserID": userId.toString()},
      };

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

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null && data['value'] is List) {
          final list = data['value'] as List;
          return list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /api/Construction/General/v1/InboxDetails/{timeStamp}/{accessPoint}
  Future<List<Map<String, dynamic>>> fetchInboxDetails({
    required String menuCode,
    required String menuLinkCode,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return [];
      final user = await LocalStorageService.getUser();
      final userId = user?.userId.toString() ?? '2';

      final url = AppUrls.getInboxDetailsUrl(accessPoint: accessPoint);

      final payload = {
        "Head": {
          "UserID": userId,
          "MenuLinkCode": menuLinkCode,
          "MenuCode": menuCode,
        },
      };

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

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null && data['value'] is List) {
          final list = data['value'] as List;
          return list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// POST /api/Construction/General/v1/{Approve|Forward|Reject}/{timeStamp}/{accessPoint}
  /// Used for Construction document inbox approvals (invoices, contract bills, wage payments, etc.)
  Future<bool> processGeneralApproval({
    required int key,
    required String
    approvalStatus, // "A" (Approve), "F" (Forward), "R" (Reject)
    required String menuCode,
    required String menuLinkCode,
    Map<String, dynamic>? rawItem,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return false;
      final user = await LocalStorageService.getUser();
      final userId = user?.userId.toString() ?? '2';

      final String url;
      if (approvalStatus == 'A') {
        url = AppUrls.getGeneralApproveUrl(accessPoint: accessPoint);
      } else if (approvalStatus == 'F') {
        url = AppUrls.getGeneralForwardUrl(accessPoint: accessPoint);
      } else {
        url = AppUrls.getGeneralRejectUrl(accessPoint: accessPoint);
      }

      final payload = {
        "Head": {
          "UserID": userId,
          "Key": key.toString(),
          "MenuCode": menuCode,
          "MenuLinkCode": menuLinkCode,
          "ApprovalStatus": approvalStatus,
          if (rawItem?['BranchID'] != null)
            "BranchID": rawItem!['BranchID'].toString(),
        },
      };

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

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          final err = data['error'];
          if (err is Map && err.isNotEmpty) {
            return false;
          }
          if (data['value'] is List && (data['value'] as List).isNotEmpty) {
            final first = (data['value'] as List).first;
            if (first is Map) {
              final errMsg =
                  first['ERRORMESSAGE']?.toString() ??
                  first['ErrorMessage']?.toString() ??
                  '';
              if (errMsg.trim().isNotEmpty) return false;
            }
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
