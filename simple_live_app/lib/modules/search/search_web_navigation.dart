/// 手机网站可能用新窗口或 SPA 路由进入房间，不能仅依赖加载回调。
class SearchWebNavigation {
  static const handlerName = 'simpleLiveSearchRoom';

  static const script = r'''
(function () {
  if (window.__simpleLiveSearchNavigation) return;
  window.__simpleLiveSearchNavigation = true;
  function report(value) {
    if (typeof value !== 'string' || !value) return;
    var bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') return;
    try {
      var url = new URL(value, window.location.href);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
      var pending = bridge.callHandler('simpleLiveSearchRoom', url.href);
      if (pending && typeof pending.catch === 'function') pending.catch(function () {});
    } catch (_) {}
  }
  function reportLocation() { report(window.location.href); }
  document.addEventListener('click', function (event) {
    var target = event.target;
    if (target && target.nodeType !== 1) target = target.parentElement;
    var link = target && typeof target.closest === 'function' && target.closest('a[href]');
    if (link) report(link.href);
  }, true);
  // Android 的 JS 新窗口回调可能没有 URL，先记录目标再沿用网站行为。
  var originalOpen = window.open;
  window.open = function (url) {
    report(url);
    return originalOpen.apply(this, arguments);
  };
  ['pushState', 'replaceState'].forEach(function (name) {
    var original = window.history[name];
    window.history[name] = function () {
      var result = original.apply(this, arguments);
      reportLocation();
      return result;
    };
  });
  window.addEventListener('popstate', reportLocation);
  window.addEventListener('hashchange', reportLocation);
  window.addEventListener('flutterInAppWebViewPlatformReady', reportLocation);
})();
''';
}
