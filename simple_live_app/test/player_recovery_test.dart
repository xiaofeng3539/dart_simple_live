import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  // 测试不初始化持久化设置。
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Player implements Player {
  int opens = 0;
  int jumps = 0;
  @override
  PlayerState state = const PlayerState(playing: true, buffering: true);
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opens++;
  }

  @override
  Future<void> jump(int index) async {
    jumps++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room extends LiveRoomController {
  _Room({Site? source})
      : super(pSite: source ?? Sites.allSites['huya']!, pRoomId: '1');
  final fake = _Player();
  @override
  Player get player => fake;
  @override
  Future<void> initializePlayer() async {}
}

class _Huya extends HuyaSite {
  int calls = 0;
  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    calls++;
    return LivePlayUrl(urls: [
      'https://first/live.flv?token=new',
      'https://next/live.flv?token=new'
    ]);
  }
}

class _FlakyHuya extends HuyaSite {
  int calls = 0;
  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    calls++;
    if (calls == 1) throw StateError('暂时无法获取播放地址');
    return LivePlayUrl(urls: ['https://example.com/live.flv']);
  }
}

class _Bili extends BiliBiliSite {
  int calls = 0;
  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    calls++;
    return LivePlayUrl(urls: [
      'https://first/live.flv?token=new',
      'https://next/live.flv?token=new',
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('wakelock_plus'), (_) async => null);
  setUp(() => Get.put<AppSettingsController>(_Settings()));
  tearDown(() => Get.reset());
  test('重试当前线路必须重新打开连接', () async {
    final room = _Room();
    room.playUrls.add('https://example.com/live.flv');
    room.currentLineIndex = 0;
    room.setPlayer();
    await Future<void>.delayed(Duration.zero);
    expect(room.fake.opens, 1);
    expect(room.fake.jumps, 0);
  });
  testWidgets('首次获取播放地址失败后只重试一次并启动播放', (tester) async {
    final source = _FlakyHuya();
    final room = _Room(
        source: Site(id: 'huya', name: '', logo: '', liveSite: source));
    room.detail.value = LiveRoomDetail(
        roomId: '1',
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: true,
        url: '',
        data: '');
    room.qualites.add(LivePlayQuality(quality: '原画', data: {}));
    room.currentQuality = 0;

    room.getPlayUrl();
    await tester.pump();
    expect(source.calls, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(source.calls, 2);
    expect(room.fake.opens, 1);
  });
  testWidgets('持续缓冲15秒切换备用线路', (tester) async {
    final room = _Room();
    room.liveStatus.value = true;
    room.playUrls.addAll([
      'https://first.example.com/live.flv',
      'https://next.example.com/live.flv'
    ]);
    room.currentLineIndex = 0;
    room.mediaBuffering(true);
    await tester.pump(const Duration(seconds: 14));
    expect(room.fake.opens, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(room.currentLineIndex, 1);
    expect(room.fake.opens, 1);
    room.mediaBuffering(false);
  });
  testWidgets('缓冲恢复后不切换，后台不自动重连', (tester) async {
    final room = _Room();
    room.liveStatus.value = true;
    room.playUrls.add('https://first.example.com/live.flv');
    room.currentLineIndex = 0;
    room.mediaBuffering(true);
    room.mediaBuffering(false);
    await tester.pump(const Duration(seconds: 16));
    expect(room.fake.opens, 0);
    room.isBackground = true;
    room.mediaBuffering(true);
    await tester.pump(const Duration(seconds: 16));
    expect(room.fake.opens, 0);
    room.mediaBuffering(false);
  });
  testWidgets('健康播放的错误日志不重新打开视频', (tester) async {
    final room = _Room();
    room.playUrls.addAll(['https://first/live.flv', 'https://next/live.flv']);
    room.currentLineIndex = 0;
    room.fake.state = const PlayerState(playing: true);
    room.mediaError('解码器暂时报告错误');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(room.fake.opens, 0);
  });
  testWidgets('同一次断流的多条错误和结束通知只切线一次', (tester) async {
    final room = _Room();
    room.playUrls.addAll(['https://first/live.flv', 'https://next/live.flv']);
    room.currentLineIndex = 0;
    room.fake.state = const PlayerState(completed: true);
    room.mediaError('网络错误');
    await tester.pump();
    room.mediaError('流读取错误');
    await tester.pump();
    room.mediaEnd();
    await tester.pump();
    expect(room.fake.opens, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(room.fake.opens, 1);
  });
  testWidgets('错误后恢复进度不打断当前连接', (tester) async {
    final room = _Room();
    room.playUrls.add('https://first/live.flv');
    room.currentLineIndex = 0;
    room.mediaError('短暂网络错误');
    await tester.pump();
    room.fake.state = const PlayerState(
        playing: true, buffering: true, position: Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(room.fake.opens, 0);
  });
  testWidgets('重复缓冲通知不延长断流超时', (tester) async {
    final room = _Room();
    room.liveStatus.value = true;
    room.playUrls.addAll(['https://first/live.flv', 'https://next/live.flv']);
    room.currentLineIndex = 0;
    room.mediaBuffering(true);
    await tester.pump(const Duration(seconds: 10));
    room.mediaBuffering(true);
    await tester.pump(const Duration(seconds: 5));
    expect(room.fake.opens, 1);
    room.mediaBuffering(false);
  });
  testWidgets('缓冲时 playing 为 false 仍可恢复卡住的流', (tester) async {
    final room = _Room();
    room.liveStatus.value = true;
    room.fake.state = const PlayerState(buffering: true);
    room.playUrls.addAll(['https://first/live.flv', 'https://next/live.flv']);
    room.currentLineIndex = 0;
    room.mediaBuffering(true);
    await tester.pump(const Duration(seconds: 15));
    expect(room.fake.opens, 1);
    room.mediaBuffering(false);
  });
  testWidgets('手动切线取消上一条流待处理的错误', (tester) async {
    final room = _Room();
    room.playUrls.addAll(['https://first/live.flv', 'https://next/live.flv']);
    room.currentLineIndex = 0;
    room.mediaError('旧线路错误');
    room.changePlayLine(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(room.fake.opens, 1);
    expect(room.currentLineIndex, 1);
  });
  testWidgets('旧流结束通知不关闭当前正常播放的直播', (tester) async {
    final room = _Room();
    room.liveStatus.value = true;
    room.playUrls.add('https://first/live.flv');
    room.currentLineIndex = 0;
    room.fake.state = const PlayerState(playing: true);
    room.mediaEnd();
    await tester.pump(const Duration(seconds: 3));
    expect(room.fake.opens, 0);
    expect(room.liveStatus.value, isTrue);
  });
  testWidgets('虎牙真正断流恢复时重新获取鉴权', (tester) async {
    final site = _Huya();
    final room =
        _Room(source: Site(id: 'huya', name: '', logo: '', liveSite: site));
    room.detail.value = LiveRoomDetail(
        roomId: '1',
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: true,
        url: '',
        data: '');
    room.qualites.add(LivePlayQuality(quality: '原画', data: {}));
    room.currentQuality = 0;
    room.currentLineIndex = 0;
    room.playUrls.addAll([
      'https://first/live.flv?token=old',
      'https://next/live.flv?token=old'
    ]);
    room.mediaError('断流');
    await tester.pump(const Duration(seconds: 3));
    expect(site.calls, 1);
    expect(room.playUrls.last, contains('token=new'));
    expect(room.fake.opens, 1);
    expect(room.currentLineIndex, 1);
  });
  testWidgets('B站断流时刷新过期播放地址', (tester) async {
    final site = _Bili();
    final room = _Room(
        source: Site(id: 'bilibili', name: '', logo: '', liveSite: site));
    room.detail.value = LiveRoomDetail(
        roomId: '1', title: '', cover: '', userName: '', userAvatar: '',
        online: 0, status: true, url: '', data: '');
    room.qualites.add(LivePlayQuality(quality: '原画', data: 10000));
    room.currentQuality = 0;
    room.currentLineIndex = 0;
    room.playUrls.addAll([
      'https://first/live.flv?token=old',
      'https://next/live.flv?token=old',
    ]);
    room.mediaError('断流');
    await tester.pump(const Duration(seconds: 3));
    expect(site.calls, 1);
    expect(room.playUrls.last, contains('token=new'));
    expect(room.fake.opens, 1);
    expect(room.currentLineIndex, 1);
  });
}
