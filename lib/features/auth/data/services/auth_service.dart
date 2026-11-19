import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../models/user_model.dart';

class LoginResult {
  final bool isSuccess;
  final UserModel? user;
  final String? errorMessage;

  LoginResult({
    required this.isSuccess,
    this.user,
    this.errorMessage,
  });
}

class AuthService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<LoginResult> login({
    required String loginId,
    required String password,
  }) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) {
        return LoginResult(
          isSuccess: false,
          errorMessage: 'Access Point missing. Please reconnect to your company.',
        );
      }

      final url = AppUrls.getLoginUrl(
        accessPoint: accessPoint,
        loginId: loginId,
        password: password,
      );

      final response = await _dio.get(
        url,
        options: Options(
          headers: {'Accept': 'application/json'},
        ),
      );

      debugPrint('🌐 [LOGIN URL]: $url');
      debugPrint('📥 [LOGIN HTTP STATUS]: ${response.statusCode}');
      debugPrint('📦 [LOGIN FULL RESPONSE]: ${jsonEncode(response.data)}');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null &&
            data['value'] is List &&
            (data['value'] as List).isNotEmpty) {
          final firstItem = (data['value'] as List).first as Map<String, dynamic>;

          debugPrint('📋 [LOGIN RESPONSE FIELDS (${firstItem.length} items)]:');
          firstItem.forEach((k, v) {
            debugPrint('   👉 $k: $v (${v.runtimeType})');
          });

          // Check for any potential punch anywhere / online punch field variations
          final punchKeys = firstItem.keys.where((k) {
            final lk = k.toLowerCase();
            return lk.contains('punch') ||
                lk.contains('online') ||
                lk.contains('anywhere') ||
                lk.contains('location') ||
                lk.contains('geo');
          }).toList();

          if (punchKeys.isNotEmpty) {
            debugPrint('🎯 [MATCHING PUNCH/ANYWHERE FIELDS FOUND]:');
            for (final k in punchKeys) {
              debugPrint('   ⭐ "$k" => ${firstItem[k]} (type: ${firstItem[k].runtimeType})');
            }
          } else {
            debugPrint('ℹ️ [No explicit "punch/online/anywhere" field detected in this response]');
          }
          
          final errorMessage = firstItem['ErrorMessage'] as String?;
          if (errorMessage != null && errorMessage.isNotEmpty) {
            return LoginResult(
              isSuccess: false,
              errorMessage: errorMessage,
            );
          }

          final user = UserModel.fromJson(firstItem);

          // Also check explicit Active / IsActive / Status flag if present in response
          final isActiveRaw =
              firstItem['IsActive'] ?? firstItem['Active'] ?? firstItem['Status'];
          bool isExplicitlyInactive = false;
          if (isActiveRaw != null) {
            final activeStr = isActiveRaw.toString().trim().toLowerCase();
            if (activeStr == 'false' ||
                activeStr == '0' ||
                activeStr == 'n' ||
                activeStr == 'inactive') {
              isExplicitlyInactive = true;
            }
          }

          if (user.userId <= 0 || isExplicitlyInactive) {
            await LocalStorageService.clearUserSession();
            return LoginResult(
              isSuccess: false,
              errorMessage: 'User not Active',
            );
          }

          // Save user session in local storage
          await LocalStorageService.saveUser(user);
          if (user.branchId > 0) {
            await LocalStorageService.saveUserDefaultBranchId(user.branchId);
          }
          if (user.branchName.isNotEmpty) {
            await LocalStorageService.saveUserDefaultBranchName(user.branchName);
          }
          await LocalStorageService.saveSessionPassword(password);
          await LocalStorageService.saveOnlinePunchAnywhere(user.onlinePunchAnywhere);
          await LocalStorageService.setBiometricVerified(false);
          debugPrint(
            '💾 [AuthService] Saved user session. Home BranchID: ${user.branchId}, Home BranchName: "${user.branchName}", OnlinePunchAnywhere: ${user.onlinePunchAnywhere}, PunchNeeded: ${user.punchNeeded}, BranchStartTime: ${user.branchStartTime}, BranchEndTime: ${user.branchEndTime}',
          );

          return LoginResult(
            isSuccess: true,
            user: user,
          );
        }

        if (data['error'] != null) {
          final errMsg = _extractServerErrorMessage(data);
          if (errMsg != null && errMsg.isNotEmpty) {
            return LoginResult(
              isSuccess: false,
              errorMessage: errMsg,
            );
          }
        }
      }

      return LoginResult(
        isSuccess: false,
        errorMessage: 'Invalid username or password.',
      );
    } on DioException catch (dioErr) {
      final serverMsg = _extractServerErrorMessage(dioErr.response?.data);
      final statusCode = dioErr.response?.statusCode;
      return LoginResult(
        isSuccess: false,
        errorMessage: serverMsg ??
            (statusCode != null
                ? 'Server error (HTTP $statusCode). Please contact support or try again.'
                : 'Unable to connect to server. Please check your network and try again.'),
      );
    } catch (e) {
      return LoginResult(
        isSuccess: false,
        errorMessage: 'Unable to connect to server. Please check your network and try again.',
      );
    }
  }

  String? _extractServerErrorMessage(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      final errObj = data['error'];
      if (errObj is Map) {
        final msg = errObj['Message']?.toString() ??
            errObj['message']?.toString() ??
            errObj['ExceptionMessage']?.toString();
        if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      } else if (errObj != null && errObj.toString().trim().isNotEmpty && errObj.toString() != '{}') {
        return errObj.toString().trim();
      }
      final topMsg = data['Message']?.toString() ??
          data['message']?.toString() ??
          data['ErrorMessage']?.toString();
      if (topMsg != null && topMsg.trim().isNotEmpty) return topMsg.trim();
    } else if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }
}
