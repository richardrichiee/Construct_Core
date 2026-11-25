import 'package:dio/dio.dart';
import '../../../../core/network/app_urls.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../models/employee_details_model.dart';

class EmployeeService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<EmployeeDetailsModel?> fetchEmployeeDashboard({String? date}) async {
    try {
      final accessPoint = await LocalStorageService.getAccessPoint();
      if (accessPoint == null || accessPoint.isEmpty) return null;
      final user = await LocalStorageService.getUser();
      final employeeId = user?.employeeId ?? 0;
      if (employeeId <= 0) return null;

      final url = AppUrls.getEmployeeDashboardUrl(
        accessPoint: accessPoint,
        employeeId: employeeId,
        param: 'S',
        date: date,
      );

      final response = await _dio.get(
        url,
        options: Options(
          headers: {'Accept': 'application/json'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['value'] != null && data['value']['Table'] != null) {
          final tableList = data['value']['Table'] as List;
          final table1List = data['value']['Table1'] as List? ?? [];
          if (tableList.isNotEmpty) {
            final details = EmployeeDetailsModel.fromJson(
              tableList.first as Map<String, dynamic>,
              table1: table1List,
            );
            if (details.branchId > 0) {
              final existingDefault =
                  await LocalStorageService.getUserDefaultBranchId();
              if (existingDefault == null || existingDefault <= 0) {
                await LocalStorageService.saveUserDefaultBranchId(
                  details.branchId,
                );
              }
            }
            if (details.branchName.isNotEmpty) {
              final existingDefaultName =
                  await LocalStorageService.getUserDefaultBranchName();
              if (existingDefaultName == null || existingDefaultName.isEmpty) {
                await LocalStorageService.saveUserDefaultBranchName(
                  details.branchName,
                );
              }
            }
            return details;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
