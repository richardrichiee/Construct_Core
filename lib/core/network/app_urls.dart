class AppUrls {
  static const String baseUrl = 'http://122.165.40.92/TestConstructionAPI/';

  static String get timestamp {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Endpoint: /api/Construction/Mobile/v1/GetaccessPoint/{accessID}/{timeStamp}
  static String getAccessPointUrl(String accessID) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/GetaccessPoint/$accessID/$time';
  }

  /// Endpoint: /api/Construction/Mobile/v1/Login/{accessPoint}/{timeStamp}/{LoginID}/{password}
  static String getLoginUrl({
    required String accessPoint,
    required String loginId,
    required String password,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/Login/$accessPoint/$time/$loginId/$password';
  }

  /// Endpoint: /api/Construction/Mobile/v1/BranchList/{accessPoint}/{timeStamp}/{UserID}
  static String getBranchListUrl({
    required String accessPoint,
    required int userId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/BranchList/$accessPoint/$time/$userId';
  }

  /// Endpoint: /api/Construction/Mobile/v1/FinancialYearList/{accessPoint}/{timeStamp}/{UserID}
  static String getFinancialYearListUrl({
    required String accessPoint,
    required int userId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/FinancialYearList/$accessPoint/$time/$userId';
  }

  /// Endpoint: /api/Construction/Mobile/v1/Menu/{accessPoint}/{timeStamp}/{UserID}
  static String getMobileMenuUrl({
    required String accessPoint,
    required int userId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/Menu/$accessPoint/$time/$userId';
  }

  /// Endpoint: /api/Construction/Mobile/v1/CalculationPeriod/{accessPoint}/{timeStamp}/{BranchID}
  static String getCalculationPeriodUrl({
    required String accessPoint,
    required int branchId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/CalculationPeriod/$accessPoint/$time/$branchId';
  }

  /// Endpoint: /api/Construction/Mobile/v1/CalculationDates/{accessPoint}/{timeStamp}/{CalcPeriodID}
  static String getCalculationDatesUrl({
    required String accessPoint,
    required int calcPeriodId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/CalculationDates/$accessPoint/$time/$calcPeriodId';
  }

  /// Endpoint: GET /api/Construction/CalculationPeriod/v1/List/{Page}/{timeStamp}/{accessPoint}
  static String getCalculationPeriodListUrl({
    int page = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/CalculationPeriod/v1/List/$page/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/DailyAttendance/v1/GetDate/{CalcperiodID}/{timeStamp}/{accessPoint}
  static String getDailyAttendanceDatesUrl({
    required int calcPeriodId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/DailyAttendance/v1/GetDate/$calcPeriodId/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/LabourCategory/v1/List/{Page}/{timeStamp}/{accessPoint}
  static String getLabourCategoryListUrl({
    int page = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LabourCategory/v1/List/$page/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/LabourGroup/v1/List/{Page}/{timeStamp}/{accessPoint}
  static String getLabourGroupListUrl({
    int page = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LabourGroup/v1/List/$page/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/General/v1/GetGeneralData/{timeStamp}/{accessPoint}/0/LabourGroup
  static String getLabourGroupGeneralUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/GetGeneralData/$time/$accessPoint/0/LabourGroup';
  }

  /// Endpoint: POST /api/Construction/DailyAttendance/v1/Get/{timeStamp}/{accessPoint}
  static String getDailyAttendanceGetUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/DailyAttendance/v1/Get/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/DailyAttendance/v1/Save/{id}/{calcid}/{branchId}/{finyearId}/{userId}/{timeStamp}/{accessPoint}
  /// Note: The backend C# controller internally replaces:
  ///   .Replace("[userId]", branchId).Replace("[branchId]", finyearId).Replace("[finyearId]", userId)
  /// Therefore, the URL path slots must pass branchId, finYearId, and userId in that order.
  static String getDailyAttendanceSaveUrl({
    int id = 0,
    required int calcId,
    required int userId,
    required int branchId,
    int finYearId = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/DailyAttendance/v1/Save/$id/$calcId/$branchId/$finYearId/$userId/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/DailyAttendance/v1/Delete/{id}/{timeStamp}/{accessPoint}
  static String getDailyAttendanceDeleteUrl({
    required int id,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/DailyAttendance/v1/Delete/$id/$time/$accessPoint';
  }

  /// Endpoint: /api/Construction/General/v1/EmployeeDashBoard/{accessPoint}/{timeStamp}?iD={iD}&param={param}&Date={Date}
  static String getEmployeeDashboardUrl({
    required String accessPoint,
    required int employeeId,
    dynamic param = 'S',
    String? date,
  }) {
    final time = timestamp;
    final effectiveDate = (date != null && date.isNotEmpty)
        ? date
        : DateTime.now().toIso8601String().substring(0, 10);
    return '${baseUrl}api/Construction/General/v1/EmployeeDashBoard/$accessPoint/$time?iD=$employeeId&param=$param&Date=$effectiveDate';
  }

  /// Endpoint: /api/Construction/General/v1/DashBoard/{accessPoint}/{timeStamp}?Type={Type}&MonthCode={MonthCode}
  static String getGeneralDashboardUrl({
    required String accessPoint,
    String? monthCode,
    String type = 'A',
  }) {
    final time = timestamp;
    final monthParam = (monthCode != null && monthCode.isNotEmpty)
        ? '&MonthCode=$monthCode'
        : '';
    return '${baseUrl}api/Construction/General/v1/DashBoard/$accessPoint/$time?Type=$type$monthParam';
  }

  /// Endpoint: GET /api/Construction/LeaveApplication/v1/List/{Page}/{timeStamp}/{accessPoint}
  static String getLeaveApplicationListUrl({
    int page = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/List/$page/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/LeaveApplication/v1/Get/{id}/{timeStamp}/{accessPoint}
  static String getLeaveApplicationDetailsUrl({
    required int key,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/Get/$key/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/LeaveApplication/v1/Calculation/{timeStamp}/{accessPoint}
  static String getLeaveApplicationCalculationUrl({
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/Calculation/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/General/v1/GetUserRights/{timeStamp}/{accessPoint}/{MenuCode}/{UserID}/{BranchID}
  static String getUserRightsUrl({
    required String accessPoint,
    required int menuCode,
    required int userId,
    required int branchId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/GetUserRights/$time/$accessPoint/$menuCode/$userId/$branchId';
  }

  /// Endpoint: POST /api/Construction/LeaveApplication/v1/Save/{id}/{userId}/{timeStamp}/{accessPoint}
  static String getSaveLeaveApplicationUrl({
    int id = 0,
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/Save/$id/$userId/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/Mobile/v1/InboxCount/{accessPoint}/{timeStamp}/{UserID}
  static String getInboxCountUrl({
    required String accessPoint,
    required int userId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/InboxCount/$accessPoint/$time/$userId';
  }

  /// Alias for backward compatibility
  static String getNotificationCountUrl({
    required String accessPoint,
    required int userId,
    dynamic param = 'Count',
  }) {
    return getInboxCountUrl(accessPoint: accessPoint, userId: userId);
  }

  /// Endpoint: GET /api/Construction/Mobile/v1/InboxData/{accessPoint}/{timeStamp}/{UserID}
  static String getInboxDataUrl({
    required String accessPoint,
    required int userId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/InboxData/$accessPoint/$time/$userId';
  }

  /// Endpoint: POST /api/Construction/General/v1/Inbox/{timeStamp}/{accessPoint}
  static String getInboxUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/Inbox/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/General/v1/InboxDetails/{timeStamp}/{accessPoint}
  static String getInboxDetailsUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/InboxDetails/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/General/v1/Approve/{timeStamp}/{accessPoint}
  static String getGeneralApproveUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/Approve/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/General/v1/Forward/{timeStamp}/{accessPoint}
  static String getGeneralForwardUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/Forward/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/General/v1/Reject/{timeStamp}/{accessPoint}
  static String getGeneralRejectUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/Reject/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/LeaveCancellation/v1/List/{Page}/{timeStamp}/{accessPoint}
  static String getLeaveCancellationListUrl({
    int page = 1,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveCancellation/v1/List/$page/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/LeaveCancellation/v1/Get/{id}/{timeStamp}/{accessPoint}
  static String getLeaveCancellationDetailsUrl({
    required int key,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveCancellation/v1/Get/$key/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/LeaveCancellation/v1/Save/{id}/{userId}/{timeStamp}/{accessPoint}
  static String getSaveLeaveCancellationUrl({
    int id = 0,
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveCancellation/v1/Save/$id/$userId/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/ClaimForm/v1/List/{timeStamp}/{accessPoint}
  static String getClaimListUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/List/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/ClaimForm/v1/Get/{id}/{timeStamp}/{accessPoint}
  static String getClaimDetailsUrl({
    required int key,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/Get/$key/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ClaimForm/v1/Save/{id}/{userId}/{timeStamp}/{accessPoint}
  static String getSaveClaimUrl({
    int id = 0,
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/Save/$id/$userId/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ClaimForm/v1/GetRate/{timeStamp}/{accessPoint}
  static String getClaimRateUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/GetRate/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ClaimForm/v1/Delete/{id}/{timeStamp}/{accessPoint}
  static String getDeleteClaimUrl({
    required int id,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/Delete/$id/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/ClaimMaster/v1/List/{timeStamp}/{accessPoint}
  static String getClaimMasterListUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimMaster/v1/List/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/General/v1/GetGeneralData/{timeStamp}/{accessPoint}/0/ClaimMaster
  static String getClaimMasterUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/GetGeneralData/$time/$accessPoint/0/ClaimMaster';
  }

  /// Endpoint: GET /api/Construction/General/v1/GetGeneralData/{timeStamp}/{accessPoint}/0/LeaveMaster
  static String getLeaveMasterUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/General/v1/GetGeneralData/$time/$accessPoint/0/LeaveMaster';
  }

  /// Endpoint: POST /api/Construction/LeaveApplication/v1/Filter/{timeStamp}/{accessPoint}
  static String getLeaveEmpSearchUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/Filter/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/LeaveApplication/v1/Approve_Or_Forward/{timeStamp}/{accessPoint}
  static String getLeaveApproveOrForwardUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/LeaveApplication/v1/Approve_Or_Forward/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ClaimForm/v1/EmpSearch/{timeStamp}/{accessPoint}
  static String getClaimEmpSearchUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/EmpSearch/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ClaimForm/v1/Approve_Or_Forward/{timeStamp}/{accessPoint}
  static String getClaimApproveOrForwardUrl({required String accessPoint}) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ClaimForm/v1/Approve_Or_Forward/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/Mobile/v1/SaveBranchLocation/{accessPoint}/{timeStamp}/{UserID}/{BranchID}/{Latitude}/{Longitude}/{Radius}
  static String getSaveBranchLocationUrl({
    required String accessPoint,
    required int userId,
    required int branchId,
    required double latitude,
    required double longitude,
    required double radius,
  }) {
    final time = timestamp;
    final radiusStr = radius.round().toString();
    return '${baseUrl}api/Construction/Mobile/v1/SaveBranchLocation/$accessPoint/$time/$userId/$branchId/$latitude/$longitude/$radiusStr';
  }

  /// Endpoint: GET /api/Construction/Mobile/v1/GetLastAttendance/{accessPoint}/{timeStamp}/{BranchID}/{EmployeeID}
  static String getLastAttendanceUrl({
    required String accessPoint,
    required int branchId,
    required int employeeId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/GetLastAttendance/$accessPoint/$time/$branchId/$employeeId';
  }

  /// Endpoint: GET /api/Construction/Mobile/v1/GetHistoryAttendance/{accessPoint}/{timeStamp}/{BranchID}/{EmployeeID}
  static String getHistoryAttendanceUrl({
    required String accessPoint,
    required int branchId,
    required int employeeId,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/GetHistoryAttendance/$accessPoint/$time/$branchId/$employeeId';
  }

  /// Endpoint: POST /api/Construction/Attendance/v1/Save/{id}/{userId}/{timeStamp}/{accessPoint}
  static String getSaveAttendanceUrl({
    int id = 0,
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Attendance/v1/Save/$id/$userId/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/Mobile/v1/UpdatePassword/{UserID}/{timeStamp}/{accessPoint}
  static String getUpdatePasswordUrl({
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/Mobile/v1/UpdatePassword/$userId/$time/$accessPoint';
  }

  /// Endpoint: POST /api/Construction/ChangePassWord/v1/Save/{id}/{UserID}/{timeStamp}/{accessPoint}
  static String getChangePasswordSaveUrl({
    int id = 0,
    required int userId,
    required String accessPoint,
  }) {
    final time = timestamp;
    final saveId = id > 0 ? id : userId;
    return '${baseUrl}api/Construction/ChangePassWord/v1/Save/$saveId/$userId/$time/$accessPoint';
  }

  /// Endpoint: GET /api/Construction/ChangePassWord/v1/Details/{id}/{timeStamp}/{accessPoint}
  static String getChangePasswordDetailsUrl({
    required int id,
    required String accessPoint,
  }) {
    final time = timestamp;
    return '${baseUrl}api/Construction/ChangePassWord/v1/Details/$id/$time/$accessPoint';
  }
}
