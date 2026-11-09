import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Native implements NativePlayer {
  final properties = <String, String>{};
  int writes = 0;
  @override
  Future<void> setProperty(String property, String value,
      {bool waitForInitialization = true}) async {
    properties[property] = value;
    writes++;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  final NativePlayer platform = _Native();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness with PlayerMixin {
  final _fake = _Player();
  @override
  Player get player => _fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.put<AppSettingsController>(_Settings()));
  tearDown(() => Get.reset());
  test('起播缓冲按平台配置，保留缓存上限与断流保护', () async {
    final controller = _Harness();
    await Future.wait([controller.initializePlayer(), controller.initializePlayer()]);
    final native = controller.player.platform as _Native;
    expect(native.properties['cache-pause-wait'], Platform.isWindows ? '0.5' : '2');
    expect(native.properties['cache-pause-initial'], 'yes');
    expect(native.properties['cache-pause'], 'yes');
    expect(native.properties['cache-secs'], '20');
    expect(native.properties['cache-on-disk'], 'no');
    expect(native.properties['interpolation'], 'no');
    expect(native.properties['video-sync'], 'audio');
    expect(native.properties.containsKey('fps'), isFalse);
    expect(native.properties.containsKey('vf'), isFalse);
    expect(native.properties.containsKey('override-display-fps'), isFalse);
    final writes = native.writes;
    await controller.initializePlayer();
    expect(native.writes, writes);
  });
}
