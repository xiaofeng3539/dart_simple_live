# Simple Live 项目交接

更新时间：2026-09-26  
项目目录：`E:\2\dart_simple_live-master`

## 项目概况

- Flutter 多平台直播聚合客户端。
- `simple_live_app`：主应用，包含 Windows、Android、iOS、macOS、Linux 客户端。
- `simple_live_tv_app`：Android TV 客户端。
- `simple_live_core`：直播平台数据、播放信息和弹幕等核心逻辑。
- `simple_live_console`：核心库的控制台程序。
- 本机 Flutter：3.44.8 stable，Dart 3.12.2。
- Flutter SDK 已确认在 `D:\Tool\Flutter\flutter`；2026-09-26 已通过该 SDK 完成 Flutter 版本读取、Windows Release 编译、ZIP 打包和产物运行退出检查。开始新聊天时可复用此环境记录，不需要把 SDK 识别当作项目工作重新执行。
- Flutter 仓库被当前 Windows 用户判定为 dubious ownership 时，在当前 PowerShell 进程设置：

  ```powershell
  $env:GIT_CONFIG_COUNT='1'
  $env:GIT_CONFIG_KEY_0='safe.directory'
  $env:GIT_CONFIG_VALUE_0='D:/Tool/Flutter/flutter'
  ```

  这是进程级 Git 配置，不会改写全局 Git 设置。

## 已完成的修改

### Windows 关闭与托盘

- 修复退出时 Windows 弹出 `Unknown Hard Error`：Windows WebView 插件的静态 WinRT/COM 对象在 DLL 卸载时释放会触发退出错误。插件副本保存在 `simple_live_app/packages/flutter_inappwebview_windows`，相关全局对象改为进程生命周期内保留的原始指针，并通过 `dependency_overrides` 使用本地副本。
- `simple_live_app/windows/runner/main.cpp` 增加单实例互斥锁；再次启动时会尝试显示已有窗口。
- `simple_live_app/windows/runner/flutter_window.cpp` 处理窗口关闭请求、系统托盘显示/恢复和退出消息。窗口退出在消息循环结束后销毁 Flutter 窗口与 COM 环境。
- Flutter 端关闭选择支持“最小化到系统托盘”“退出应用”和“记住选择”。最近一次 UI 调整为紧凑的确认框，深色主题为深灰背景、红色退出按钮。
- 选择记录键为 `WindowsCloseAction`，定义于 `simple_live_app/lib/services/local_storage_service.dart`。

### Flutter 与依赖

- 主 App 与 TV 的 `.fvmrc`、CI 工作流和 README 已从 Flutter 3.38.3 更新为 3.44 系列；本机固定版本为 3.44.8。
- App 已升级可兼容的依赖，包括 `remixicon`、`flutter_smart_dialog`、`canvas_danmaku`、`permission_handler`、`image_gallery_saver_plus`、`flutter_lints`、`flutter_launcher_icons`。
- 为适配新版弹幕 API，两个 `duration` 参数改为 `double`。
- Windows Release 编译在 Flutter 3.44.8 下成功。

### 远程同步创建房间

- 在 `simple_live_app/lib/modules/sync/remote_sync/room/remote_sync_room_controller.dart` 中补上连接失败处理和明确的错误对话框。远程同步不可用时提示用户返回使用局域网同步或 WebDAV，并记录底层错误。
- 已使用项目同样的 SignalR 协议复现：与 `https://sync1.nsapps.cn/sync` 的协商和连接成功，调用 `CreateRoom` 时服务器返回 `An unexpected error occurred invoking 'CreateRoom' on the server.`
- 用户明确选择保留原同步服务，不切换到社区公共服务。因此远程创建房间目前仍受服务端故障阻塞；客户端已改善错误提示，但没有声称恢复了远程房间功能。

## 关键文件

| 文件 | 用途 |
|---|---|
| `simple_live_app/lib/main.dart` | Windows 关闭选择框和 MethodChannel 处理 |
| `simple_live_app/lib/services/local_storage_service.dart` | 关闭选择的本地设置键 |
| `simple_live_app/windows/runner/main.cpp` | 单实例与 Windows 消息循环退出顺序 |
| `simple_live_app/windows/runner/flutter_window.cpp` | 关闭拦截、托盘图标和托盘菜单 |
| `simple_live_app/lib/modules/sync/remote_sync/room/remote_sync_room_controller.dart` | 远程房间连接、创建及故障提示 |
| `simple_live_app/lib/services/signalr_service.dart` | SignalR 服务地址、创建/加入房间请求 |
| `simple_live_app/pubspec.yaml` | App 依赖和本地 Windows WebView 插件覆盖 |
| `simple_live_app/packages/flutter_inappwebview_windows/windows/in_app_webview/in_app_webview_manager.h` | 修复 WebView 插件卸载期间 COM 清理错误 |
| `.github/workflows/` | App 与 TV 的 CI Flutter 版本配置 |
| `simple_live_app/.fvmrc`、`simple_live_tv_app/.fvmrc` | FVM Flutter 版本固定值 |

## 验证与当前产物

- 最近一次修改后，`flutter analyze --no-pub --no-fatal-infos` 针对 `main.dart` 和房间控制器检查通过。
- 最近一次 Windows Release 构建通过。
- 最终版本正常退出检查通过：进程退出码 `0`，检查期间 Windows System Event 26 未出现新的 `Unknown Hard Error`。
- ZIP 已核对包含 EXE、`flutter_windows.dll`、应用资源目录等运行文件。
- 当前要求只生成 ZIP，不再生成 MSIX。最新 ZIP：`dist/SimpleLive-Windows-x64.zip`（约 41 MB）。构建配置版本为 `1.11.4+11104`。
- 项目内完整 ZIP 也位于 `simple_live_app/build/dist/1.11.4+11104/simple_live_app-1.11.4+11104-windows.zip`。

## 已知问题与限制

1. **远程创建房间：**原同步服务器可以连接，但 `CreateRoom` 在服务端报内部错误。需服务维护方修复，或用户日后明确同意更换同步服务；当前提供局域网同步和 WebDAV 作为替代。
2. **App 默认测试仍是模板：**`simple_live_app/test/widget_test.dart` 是 Flutter 默认计数器测试，直接创建 `MyApp` 时没有注册 `AppSettingsController`，因此失败。这是仓库现有测试问题，尚未改写。
3. **核心库静态检查：**`simple_live_core/lib/src/huya_site.dart` 有两个未使用 import 警告；另有若干现存 lint 提示。此前分析结果为 13 项，不是本次 Windows UI 改动导致。
4. **未升级的依赖：**`file_picker`、`dynamic_color` 等大版本涉及 API 变化；部分插件与新版 `win32` 约束冲突，当前保留可编译版本。`flutter_easyrefresh` 仍是已停止维护的依赖。
5. **房间倒计时注释不符：**房间控制器注释写“5分钟”，但 `countDown` 初值为 600 秒（10分钟）。此项尚未调整。
6. **MSIX 签名：**此前生成过的 MSIX 使用的签名在本机不受信任。当前交付 ZIP，无需处理旧 MSIX。

## 下一步计划

1. 继续保持原同步服务地址；待服务端恢复后重新调用 `CreateRoom` 和 `JoinRoom` 验证完整房间流程。
2. 如果远程服务持续故障，继续使用现有局域网同步或 WebDAV。任何更换公共同步服务的方案需先说明数据流向，并取得用户同意。
3. 用最新 Release 在 Windows 上复核关闭弹窗、记住选择、退出、托盘隐藏、托盘恢复和二次启动聚焦已有窗口。
4. 后续可单独修复默认计数器模板测试，并增加真正初始化应用控制器的启动测试。
5. 依赖升级按插件兼容性分批推进；先评估 `flutter_easyrefresh` 替代方案和 `file_picker`/`dynamic_color` 的 API 迁移，再构建目标平台。
6. 任何运行时代码修改完成后，按项目要求执行检查、Windows Release 编译、ZIP 打包和产物完整性核对；本地最终包仅保留 ZIP 作为本轮交付。

## Windows ZIP 打包

项目 CI 使用 `flutter_distributor`。在 `simple_live_app` 目录执行：

```powershell
flutter_distributor package --platform windows --targets zip --skip-clean
```

工具将输出到 `simple_live_app/build/dist/1.11.4+11104/`。确认包内含 EXE、Flutter DLL 和 `data/flutter_assets`，并将最终 ZIP 复制为 `dist/SimpleLive-Windows-x64.zip`。不要添加 `msix` target，除非用户之后明确要求。

Flutter 启动命令需从 `D:\Tool\Flutter\flutter\bin\flutter.bat` 调用。Flutter SDK 首次探测若长时间无输出，可检查对应的 dart/flutter 进程和 SDK 锁；但不要仅为再次确认版本而重复启动探测。若之后构建实际失败，再按错误信息检查 SDK 状态。
