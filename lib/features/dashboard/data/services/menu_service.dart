import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../models/menu_item_model.dart';

class MenuService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<List<MenuItemModel>> fetchMenus() async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      final user = await LocalStorageService.getUser();
      if (accessPoint == null || accessPoint.trim().isEmpty || user == null) {
        return LocalStorageService.getMenus();
      }

      final url = AppUrls.getMobileMenuUrl(
        accessPoint: accessPoint.trim(),
        userId: user.userId,
      );

      final response = await _dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final rawValue = data['value'];
        final List<MenuItemModel> menus = [];

        if (rawValue is List) {
          for (final item in rawValue) {
            if (item is Map) {
              final model = MenuItemModel.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (model.name.isNotEmpty) {
                menus.add(model);
              }
            }
          }
        } else if (rawValue is Map) {
          final model = MenuItemModel.fromJson(
            Map<String, dynamic>.from(rawValue),
          );
          if (model.name.isNotEmpty) {
            menus.add(model);
          }
        }

        await LocalStorageService.saveMenus(menus);
        debugPrint(
          '📋 [MenuService] Loaded ${menus.length} dynamic menus for UserID=${user.userId}',
        );
        return menus;
      }
    } catch (e) {
      debugPrint('⚠️ [MenuService] Error fetching menus: $e');
    }

    return LocalStorageService.getMenus();
  }
}
