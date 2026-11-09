import 'dart:async';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart' as core;
import 'package:test/test.dart';

class _Bili extends BiliBiliSite {
  int calls = 0;
  final gate = Completer<void>();
  @override
  Future<Map<String, dynamic>> getRoomInfo({required String roomId}) async {
    calls++;
    await gate.future;
    return {
      'room_info': {'room_id': roomId, 'live_status': 0},
    };
  }

  @override
  Future<Map<String, String>> getHeader() async => {};
}

LiveRoomDetail room() => LiveRoomDetail(
  roomId: '1',
  title: '',
  cover: '',
  userName: '',
  userAvatar: '',
  online: 0,
  status: true,
  url: '',
);
Map<String, dynamic> playInfo(String token) => {
  'data': {
    'playurl_info': {
      'playurl': {
        'g_qn_desc': [
          {'qn': 80, 'desc': '高清'},
        ],
        'stream': [
          {
            'format': [
              {
                'codec': [
                  {
                    'codec_name': 'avc',
                    'current_qn': 80,
                    'accept_qn': [80],
                    'base_url': '/live.flv',
                    'url_info': [
                      {'host': 'https://cdn.test', 'extra': '?token=$token'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    },
  },
};
void main() {
  late Dio original;
  setUp(() {
    CoreLog.enableLog = false;
    original = core.HttpClient.instance.dio;
    core.HttpClient.instance.dio = Dio();
  });
  tearDown(() {
    core.HttpClient.instance.dio.close();
    core.HttpClient.instance.dio = original;
  });
  test(
    'Bili concurrent details share one request but later refresh reloads',
    () async {
      final site = _Bili();
      final first = site.getRoomDetail(roomId: '1');
      final second = site.getRoomDetail(roomId: '1');
      site.gate.complete();
      await Future.wait([first, second]);
      expect(site.calls, 1);
      await site.getRoomDetail(roomId: '1');
      expect(site.calls, 2);
    },
  );
  test('Bili concurrent quality consumers share prefetched request', () async {
    var calls = 0;
    final gate = Completer<void>();
    core.HttpClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          calls++;
          await gate.future;
          handler.resolve(
            Response(requestOptions: request, data: playInfo('initial')),
          );
        },
      ),
    );
    final site = _Bili();
    site.prefetchRoom('1');
    final first = site.getPlayQualites(detail: room());
    final second = site.getPlayQualites(detail: room());
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });
  test(
    'Bili playback handoff is consumed once so recovery gets a fresh URL',
    () async {
      var calls = 0;
      core.HttpClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            calls++;
            handler.resolve(
              Response(requestOptions: request, data: playInfo('$calls')),
            );
          },
        ),
      );
      final site = _Bili();
      final detail = room();
      final qualities = await site.getPlayQualites(detail: detail);
      final first = await site.getPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      final retry = await site.getPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      expect(first.urls.single, endsWith('token=1'));
      expect(retry.urls.single, endsWith('token=2'));
      expect(calls, 2);
    },
  );
  for (final entry in <String, LiveSite>{
    'douyu': DouyuSite(),
    'huya': HuyaSite(),
    'douyin': DouyinSite(),
  }.entries) {
    test(
      '${entry.key} concurrent details deduplicate but sequential refresh reloads',
      () async {
        var calls = 0;
        final gate = Completer<void>();
        core.HttpClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) async {
              calls++;
              await gate.future;
              final data = switch (entry.key) {
                'douyu' => {
                  'room': {'room_id': 1, 'show_status': 2, 'videoLoop': 0},
                },
                'huya' => {
                  'data': {'liveStatus': 'OFF'},
                },
                _ => {
                  'data': {
                    'data': [
                      {
                        'status': 4,
                        'id_str': '1',
                        'owner': {'nickname': '主播'},
                      },
                    ],
                  },
                },
              };
              handler.resolve(Response(requestOptions: request, data: data));
            },
          ),
        );
        final first = entry.value.getRoomDetail(roomId: '1');
        final second = entry.value.getRoomDetail(roomId: '1');
        gate.complete();
        final details = await Future.wait([first, second]);
        expect(details.every((room) => !room.status), isTrue);
        expect(calls, 1);
        await entry.value.getRoomDetail(roomId: '1');
        expect(calls, 2);
      },
    );
  }
  test('Bili concurrent direct URL loads coalesce and retry reloads', () async {
    var calls = 0;
    final gate = Completer<void>();
    core.HttpClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          calls++;
          await gate.future;
          handler.resolve(
            Response(requestOptions: request, data: playInfo('$calls')),
          );
        },
      ),
    );
    final site = _Bili();
    final quality = LivePlayQuality(quality: '高清', data: 80);
    final first = site.getPlayUrls(detail: room(), quality: quality);
    final second = site.getPlayUrls(detail: room(), quality: quality);
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    await site.getPlayUrls(detail: room(), quality: quality);
    expect(calls, 2);
  });
  test(
    'Douyu concurrent quality requests share only identical signing args',
    () async {
      var calls = 0;
      final gate = Completer<void>();
      core.HttpClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            calls++;
            await gate.future;
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'data': {
                    'cdnsWithName': [
                      {'cdn': 'cdn'},
                    ],
                    'multirates': [
                      {'name': '高清', 'rate': 0},
                    ],
                  },
                },
              ),
            );
          },
        ),
      );
      final site = DouyuSite();
      final first = site.getPlayQualites(detail: room());
      final second = site.getPlayQualites(detail: room());
      gate.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
      await site.getPlayQualites(detail: room());
      expect(calls, 2);
    },
  );
  test(
    'Douyu identical CDN requests coalesce but signing args stay distinct',
    () async {
      var calls = 0;
      final gate = Completer<void>();
      core.HttpClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            calls++;
            await gate.future;
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'data': {
                    'rtmp_url': 'https://cdn.test',
                    'rtmp_live': 'live.flv',
                  },
                },
              ),
            );
          },
        ),
      );
      final site = DouyuSite();
      final first = site.getPlayUrl('1', 'sign=one', 0, 'cdn');
      final second = site.getPlayUrl('1', 'sign=one', 0, 'cdn');
      final changed = site.getPlayUrl('1', 'sign=two', 0, 'cdn');
      gate.complete();
      await Future.wait([first, second, changed]);
      expect(calls, 2);
      await site.getPlayUrl('1', 'sign=one', 0, 'cdn');
      expect(calls, 3);
    },
  );
}
