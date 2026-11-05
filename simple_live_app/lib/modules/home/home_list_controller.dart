import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HomeListController extends BasePageController<LiveRoomItem> {
  final Site site;
  HomeListController(this.site);

  Future? _pendingLoad;
  Future? _pendingRefresh;

  @override
  Future loadData() {
    // Once refresh is queued, a load-more event must not slip ahead of it.
    if (_pendingRefresh != null) return _pendingRefresh!;
    return _pendingLoad ??= _load();
  }

  Future _load() async {
    try {
      await super.loadData();
    } finally {
      _pendingLoad = null;
    }
  }

  // Coalesce repeated refreshes. Never clear/reset pagination while an older
  // request is still running, otherwise it can overwrite the new first page.
  @override
  Future refreshData() => _pendingRefresh ??= _refresh();

  Future _refresh() async {
    try {
      await _pendingLoad;
      currentPage = 1;
      list.value = [];
      // Bypass the public loadData refresh gate to avoid awaiting ourselves.
      await (_pendingLoad ??= _load());
    } finally {
      _pendingRefresh = null;
    }
  }

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    var result = await site.liveSite.getRecommendRooms(page: page);

    return result.items;
  }
}
