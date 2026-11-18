import 'package:dio/dio.dart';
import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../notifications/data/services/inbox_service.dart';

class NotificationService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final _inboxService = InboxService();

  Future<int> fetchNotificationCount() async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      final user = await LocalStorageService.getUser();
      if (accessPoint != null && accessPoint.isNotEmpty && user != null && user.userId > 0) {
        try {
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
              final cntRaw = first['Cnt'] ?? first['cnt'] ?? first['Count'] ?? first['count'];
              final parsed = int.tryParse(cntRaw?.toString() ?? '');
              if (parsed != null) return parsed;
            }
          }
        } catch (_) {}
      }

      // Fallback: sum counts across all Inbox categories returned by server
      final list = await _inboxService.fetchInboxSummary();
      int total = 0;
      for (final cat in list) {
        final cnt = int.tryParse(cat['Cnt']?.toString() ?? '0') ?? 0;
        total += cnt;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}
