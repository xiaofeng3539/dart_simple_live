import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart' as core;

class _Bili extends BiliBiliSite {
  @override
  Future<Map<String, String>> getHeader() async => {};
}

class _Huya extends HuyaSite {
  int tokenCalls = 0;
  @override
  Future<String> getCndTokenInfoEx(String stream) async {
    tokenCalls++;
    return 'wsSecret=备用';
  }
}

class _Douyu extends DouyuSite {
  @override
  Future<String> getPlayUrl(
      String roomId, String args, int rate, String cdn) async {
    if (cdn == '失败') throw StateError('线路失败');
    return 'https://example.com/live.flv';
  }
}

LiveRoomDetail _detail() => LiveRoomDetail(
      roomId: '1',
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
      data: '',
    );

HuyaLineModel _line({String anti = 'wsSecret=页面', bool hls = false}) =>
    HuyaLineModel(
      line: 'https://example.com',
      streamName: 'live',
      cdnType: '',
      flvAntiCode: anti,
      hlsAntiCode: anti,
      presenterUid: 1,
      lineType: hls ? HuyaLineType.hls : HuyaLineType.flv,
    );

void main() {
  test('B站普通线路保持原顺序，mcdn 排后并去重', () async {
    final dio = core.HttpClient.instance.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: {
        'data': {
          'playurl_info': {
            'playurl': {
              'stream': [
                {
                  'format': [
                    {
                      'codec': [
                        {
                          'base_url': '/live.flv',
                          'url_info': [
                            {'host': 'https://mcdn.example.com', 'extra': ''},
                            {'host': 'https://first.example.com', 'extra': ''},
                            {'host': 'https://second.example.com', 'extra': ''},
                            {'host': 'https://first.example.com', 'extra': ''},
                          ],
                        }
                      ]
                    }
                  ]
                },
              ]
            }
          }
        },
      }));
    });
    dio.interceptors.add(interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    final urls = await _Bili().getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(quality: '', data: 10000),
    );
    expect(urls.urls, [
      'https://first.example.com/live.flv',
      'https://second.example.com/live.flv',
      'https://mcdn.example.com/live.flv',
    ]);
  });
  test('斗鱼空数据及非法地址不会变成播放链接', () async {
    final dio = core.HttpClient.instance.dio;
    dynamic responseData;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: responseData));
    });
    dio.interceptors.add(interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    for (final data in [
      null,
      {},
      {'rtmp_url': 'null', 'rtmp_live': 'null'}
    ]) {
      responseData = {'error': 1, 'data': data};
      expect(await DouyuSite().getPlayUrl('1', '', 0, ''), isEmpty);
    }
  });
  test('虎牙优先使用页面鉴权并保留清晰度', () async {
    final site = _Huya();
    final url = await site.getPlayUrl(_line(), 2000);
    expect(url, contains('.flv?wsSecret=页面'));
    expect(url, contains('&ratio=2000'));
    expect(site.tokenCalls, 0);
  });
  test('虎牙页面鉴权缺失才请求备用接口', () async {
    final site = _Huya();
    expect(await site.getPlayUrl(_line(anti: ''), 0), contains('备用'));
    expect(site.tokenCalls, 1);
  });
  test('虎牙 HLS 使用正确扩展名', () async {
    expect(await _Huya().getPlayUrl(_line(hls: true), 0), contains('.m3u8?'));
  });
  test('虎牙损坏线路不影响可用线路并去重', () async {
    final urls = await _Huya().getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(quality: '', data: {
        'urls': [_line(anti: 'fm=损坏'), _line(), _line()],
        'bitRate': 0,
      }),
    );
    expect(urls.urls, hasLength(1));
  });
  test('斗鱼单线路失败仍保留其他线路并去重', () async {
    final urls = await _Douyu().getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(
          quality: '', data: DouyuPlayData(0, ['失败', '线路一', '线路二'])),
    );
    expect(urls.urls, ['https://example.com/live.flv']);
  });
  test('抖音读取地址不会修改画质原数据', () async {
    final original = [
      'https://example.com/live.flv',
      'https://example.com/live.m3u8'
    ];
    final urls = await DouyinSite().getPlayUrls(
      detail: _detail(),
      quality: LivePlayQuality(quality: '', data: original),
    );
    urls.urls.clear();
    expect(original, hasLength(2));
  });
}
