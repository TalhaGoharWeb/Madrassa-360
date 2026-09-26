#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// ── Native startup splash ───────────────────────────────────────────────
// Borderless, centered, topmost window showing resources/splash.bmp
// (embedded in Runner.rc as IDI_SPLASH_BITMAP) while the Flutter engine
// boots. Destroyed on the first rendered frame in FlutterWindow::OnCreate.
// If the bitmap resource is missing, boot proceeds without a splash.

constexpr wchar_t kSplashWindowClass[] = L"Madrassa360Splash";
constexpr int kSplashWidth = 600;
constexpr int kSplashHeight = 400;

HWND g_splash_window = nullptr;
HBITMAP g_splash_bitmap = nullptr;

LRESULT CALLBACK SplashWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = ::BeginPaint(hwnd, &ps);
      if (g_splash_bitmap != nullptr) {
        HDC mem_dc = ::CreateCompatibleDC(hdc);
        HGDIOBJ old = ::SelectObject(mem_dc, g_splash_bitmap);
        BITMAP bm{};
        ::GetObject(g_splash_bitmap, sizeof(bm), &bm);
        ::BitBlt(hdc, 0, 0, bm.bmWidth, bm.bmHeight, mem_dc, 0, 0, SRCCOPY);
        ::SelectObject(mem_dc, old);
        ::DeleteDC(mem_dc);
      }
      ::EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

void ShowSplash(HINSTANCE instance) {
  g_splash_bitmap = static_cast<HBITMAP>(::LoadImage(
      instance, MAKEINTRESOURCE(IDI_SPLASH_BITMAP), IMAGE_BITMAP, 0, 0, 0));
  if (g_splash_bitmap == nullptr) {
    return;  // No splash bitmap — boot continues without one.
  }

  WNDCLASSW wc{};
  wc.lpfnWndProc = SplashWindowProc;
  wc.hInstance = instance;
  wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground =
      static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH));
  wc.lpszClassName = kSplashWindowClass;
  ::RegisterClassW(&wc);

  const int x = (::GetSystemMetrics(SM_CXSCREEN) - kSplashWidth) / 2;
  const int y = (::GetSystemMetrics(SM_CYSCREEN) - kSplashHeight) / 2;
  g_splash_window = ::CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kSplashWindowClass, L"Madrassa 360",
      WS_POPUP | WS_VISIBLE, x, y, kSplashWidth, kSplashHeight, nullptr,
      nullptr, instance, nullptr);
}

void DestroySplash() {
  if (g_splash_window != nullptr) {
    ::DestroyWindow(g_splash_window);
    g_splash_window = nullptr;
  }
  if (g_splash_bitmap != nullptr) {
    ::DeleteObject(g_splash_bitmap);
    g_splash_bitmap = nullptr;
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Branded splash covers engine boot (first Dart frame can take seconds
  // on cold start). Destroyed in the first-frame callback below.
  ShowSplash(::GetModuleHandle(nullptr));

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // First frame is up: drop the splash, then reveal the main window.
    DestroySplash();
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Safety net: never leave the splash on screen if the engine died
  // before its first frame.
  DestroySplash();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
