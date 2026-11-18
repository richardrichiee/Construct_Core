import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_app/core/storage/local_storage_service.dart';
import 'package:construction_app/features/dashboard/data/models/menu_item_model.dart';

void main() {
  test('MenuItemModel parses Construction API items and maps modules', () {
    final claim = MenuItemModel.fromJson({'Value': 5121, 'Name': 'Claim'});
    final application =
        MenuItemModel.fromJson({'Value': 5105, 'Name': 'Application'});
    final attendance =
        MenuItemModel.fromJson({'Value': 5057, 'Name': 'Daily Attendance'});
    final unknown =
        MenuItemModel.fromJson({'Value': 5999, 'Name': 'Material Request'});

    expect(claim.value, 5121);
    expect(claim.name, 'Claim');
    expect(claim.moduleType, MenuModuleType.claim);

    expect(application.value, 5105);
    expect(application.name, 'Application');
    expect(application.moduleType, MenuModuleType.leave);

    expect(attendance.value, 5057);
    expect(attendance.name, 'Daily Attendance');
    expect(attendance.moduleType, MenuModuleType.attendance);

    expect(unknown.value, 5999);
    expect(unknown.moduleType, MenuModuleType.unknown);
  });

  test('LocalStorageService resolves cached dynamic MenuCodes by module', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.saveMenus(const [
      MenuItemModel(value: 5121, name: 'Claim'),
      MenuItemModel(value: 5105, name: 'Application'),
      MenuItemModel(value: 5057, name: 'Daily Attendance'),
    ]);

    expect(
      await LocalStorageService.getMenuCodeForModule(
        MenuModuleType.claim,
        fallback: 15,
      ),
      5121,
    );
    expect(
      await LocalStorageService.getMenuCodeForModule(
        MenuModuleType.leave,
        fallback: 19,
      ),
      5105,
    );
    expect(
      await LocalStorageService.getMenuCodeForModule(
        MenuModuleType.attendance,
        fallback: 0,
      ),
      5057,
    );
  });
}

