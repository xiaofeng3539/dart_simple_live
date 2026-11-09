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
  testWidgets(
      'refresh setting reports system management without mode-switch controls',
      (tester) async {
    Get.put<AppSettingsController>(_Settings());
    try {
      await tester.pumpWidget(const GetMaterialApp(home: PlaySettingsPage()));
      expect(find.text('屏幕刷新率'), findsOneWidget);
      expect(find.text('系统管理'), findsOneWidget);
      await tester.tap(find.text('屏幕刷新率'));
      await tester.pumpAndSettle();
      expect(find.text('120Hz'), findsNothing);
      expect(find.textContaining('不改变直播源帧率'), findsOneWidget);
    } finally {
      Get.reset();
    }
  });
}
