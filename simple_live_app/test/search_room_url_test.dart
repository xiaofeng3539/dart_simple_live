import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/search/search_room_url.dart';

void main() {
  test('每个平台打开对应的直播网站首页', () {
    expect(
        SearchRoomUrl.homeUriFor(Constant.kBiliBili).host, 'live.bilibili.com');
    expect(SearchRoomUrl.homeUriFor(Constant.kHuya).host, 'www.huya.com');
    expect(SearchRoomUrl.homeUriFor(Constant.kDouyu).host, 'www.douyu.com');
    expect(SearchRoomUrl.homeUriFor(Constant.kDouyin).host, 'live.douyin.com');
  });

  test('识别四个平台的直播间地址', () {
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kBiliBili,
        Uri.parse('https://live.bilibili.com/12345?spm=1'),
      ),
      '12345',
    );
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kHuya,
        Uri.parse('https://www.huya.com/my_room-1'),
      ),
      'my_room-1',
    );
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kDouyu,
        Uri.parse('https://www.douyu.com/98765'),
      ),
      '98765',
    );
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kDouyu,
        Uri.parse('https://www.douyu.com/topic/event?rid=5678'),
      ),
      '5678',
    );
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kDouyin,
        Uri.parse('https://live.douyin.com/1234567890'),
      ),
      '1234567890',
    );
    expect(
      SearchRoomUrl.roomIdFor(
        Constant.kDouyin,
        Uri.parse(
            'https://www.douyin.com/root/live/921169302662?room_id=7689851218365139754'),
      ),
      '921169302662',
    );
  });

  test('首页、搜索页及其他域名不显示跳转按钮', () {
    const cases = [
      (Constant.kBiliBili, 'https://live.bilibili.com/'),
      (Constant.kBiliBili, 'https://www.bilibili.com/video/12345'),
      (Constant.kHuya, 'https://www.huya.com/g/1'),
      (Constant.kDouyu, 'https://www.douyu.com/search/abc'),
      (Constant.kDouyu, 'https://www.douyu.com/g_lol'),
      (Constant.kDouyin, 'https://www.douyin.com/search/abc?type=live'),
      (Constant.kDouyin, 'https://live.douyin.com/category'),
      (Constant.kBiliBili, 'https://live.bilibili.com.evil.test/12345'),
    ];
    for (final (site, url) in cases) {
      expect(SearchRoomUrl.roomIdFor(site, Uri.parse(url)), isNull);
    }
  });
}
