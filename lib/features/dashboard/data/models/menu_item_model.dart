enum MenuModuleType {
  claim,
  leave,
  leaveCancellation,
  attendance,
  notifications,
  unknown,
}

class MenuItemModel {
  final int value;
  final String name;

  const MenuItemModel({
    required this.value,
    required this.name,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    final rawVal =
        json['Value'] ?? json['value'] ?? json['MenuCode'] ?? json['ID'] ?? 0;
    final parsedVal = rawVal is int
        ? rawVal
        : int.tryParse(rawVal.toString()) ?? 0;
    final rawName =
        json['Name'] ?? json['name'] ?? json['MenuName'] ?? json['Title'] ?? '';

    return MenuItemModel(
      value: parsedVal,
      name: rawName.toString().trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Value': value,
      'Name': name,
    };
  }

  MenuModuleType get moduleType {
    final lower = name.trim().toLowerCase();
    if (value == 5121 ||
        value == 15 ||
        lower.contains('claim') ||
        lower.contains('expense')) {
      return MenuModuleType.claim;
    }
    if (value == 5102 ||
        lower.contains('cancellation') ||
        (lower.contains('leave') && lower.contains('cancel'))) {
      return MenuModuleType.leaveCancellation;
    }
    if (value == 5105 ||
        value == 19 ||
        lower.contains('leave') ||
        lower == 'application' ||
        lower.contains('application')) {
      return MenuModuleType.leave;
    }
    if (value == 5057 || lower.contains('attendance')) {
      return MenuModuleType.attendance;
    }
    if (lower.contains('notification') ||
        lower.contains('inbox') ||
        lower.contains('approval')) {
      return MenuModuleType.notifications;
    }
    return MenuModuleType.unknown;
  }
}

