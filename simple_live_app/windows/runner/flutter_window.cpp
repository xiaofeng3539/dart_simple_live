#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kExitMessage = WM_APP + 2;
constexpr UINT_PTR kExitTimer = 1;
constexpr UINT kShowCommand = 40001;
constexpr UINT kExitCommand = 40002;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "simple_live/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "hideToTray") {
          HideToTray();
          result->Success();
        } else if (call.method_name() == "exitApp") {
          PostMessageW(GetHandle(), kExitMessage, 0, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  EnsureTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::EnsureTrayIcon() {
  if (tray_icon_visible_) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = GetHandle();
  icon.uID = 1;
  icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  icon.uCallbackMessage = kTrayMessage;
  icon.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(icon.szTip, L"Simple Live");
  if (Shell_NotifyIconW(NIM_ADD, &icon)) {
    tray_icon_visible_ = true;
    tray_window_ = GetHandle();
  }
}

void FlutterWindow::HideToTray() {
  EnsureTrayIcon();
  if (tray_icon_visible_) ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_visible_) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = tray_window_;
  icon.uID = 1;
  Shell_NotifyIconW(NIM_DELETE, &icon);
  tray_icon_visible_ = false;
  tray_window_ = nullptr;
}

void FlutterWindow::RestoreFromTray() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE) {
    if (window_channel_) {
      window_channel_->InvokeMethod("onCloseRequest", nullptr);
    }
    return 0;
  }
  if (message == kTrayMessage) {
    if (lparam == WM_LBUTTONDBLCLK) {
      RestoreFromTray();
    } else if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, kShowCommand, L"打开 Simple Live");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, kExitCommand, L"退出 Simple Live");
      POINT cursor;
      GetCursorPos(&cursor);
      SetForegroundWindow(hwnd);
      UINT command = TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD |
                                           TPM_NONOTIFY, cursor.x, cursor.y,
                                    0, hwnd, nullptr);
      DestroyMenu(menu);
      if (command == kShowCommand) {
        RestoreFromTray();
      } else if (command == kExitCommand) {
        PostMessageW(hwnd, kExitMessage, 0, 0);
      }
    }
    return 0;
  }
  if (message == kExitMessage) {
    RemoveTrayIcon();
    SetTimer(hwnd, kExitTimer, 100, nullptr);
    return 0;
  }
  if (message == WM_TIMER && wparam == kExitTimer) {
    KillTimer(hwnd, kExitTimer);
    PostQuitMessage(0);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
