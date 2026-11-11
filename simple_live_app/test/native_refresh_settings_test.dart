import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/settings/play_settings_page.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  testWidgets('settings omit the informational refresh row and retain native FPS control', (tester) async {
    Get.put<AppSettingsController>(_Settings());
    try {
      await tester.pumpWidget(const GetMaterialApp(home: PlaySettingsPage()));
      expect(find.text('屏幕刷新率'), findsNothing);
      expect(find.text('系统管理'), findsNothing);
      expect(find.text('原生高帧率优先'), findsOneWidget);
    } finally {
      Get.reset();
    }
  });
}
