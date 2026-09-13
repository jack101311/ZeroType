#include "overlay_window.h"

#include <flutter_windows.h>

#include <algorithm>
#include <cmath>

// gdiplus.h relies on the min/max macros that NOMINMAX removes.
#include <objidl.h>
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

namespace {

constexpr wchar_t kWindowClassName[] = L"ZeroTypeOverlayWindow";
constexpr UINT kEscCancelMessage = WM_APP + 1;
constexpr UINT_PTR kAnimationTimerId = 1;
constexpr UINT kAnimationIntervalMs = 16;

// Layout constants, mirroring AppDelegate.swift.
constexpr double kHeight = 48.0;
constexpr double kMinWidth = 140.0;
constexpr double kBottomOffset = 60.0;
constexpr double kFontSize = 13.0;
constexpr double kDotLeading = 20.0;
constexpr double kDotSize = 10.0;
constexpr double kGap = 10.0;
constexpr double kWaveformWidth = 40.0;
constexpr double kWaveformHeight = 22.0;
constexpr double kCancelGap = 8.0;
constexpr double kCancelSize = 18.0;
constexpr double kCancelTrailing = 12.0;

struct Rgb {
  BYTE r, g, b;
};

Rgb ColorForStatus(const std::string& status) {
  if (status == "recording") return {255, 122, 0};
  if (status == "cancelling") return {153, 153, 153};
  if (status == "saving") return {255, 166, 0};
  if (status == "transcribing") return {99, 179, 255};
  if (status == "done") return {99, 255, 143};
  return {255, 92, 92};  // error
}

Gdiplus::Color WithAlpha(Rgb rgb, double alpha) {
  return Gdiplus::Color(static_cast<BYTE>(std::lround(alpha * 255.0)), rgb.r,
                        rgb.g, rgb.b);
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int length = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), length);
  return wide;
}

void AddRoundedRect(Gdiplus::GraphicsPath& path, Gdiplus::REAL x,
                    Gdiplus::REAL y, Gdiplus::REAL width, Gdiplus::REAL height,
                    Gdiplus::REAL radius) {
  Gdiplus::REAL d = std::min(radius * 2, std::min(width, height));
  path.AddArc(x, y, d, d, 180, 90);
  path.AddArc(x + width - d, y, d, d, 270, 90);
  path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
  path.AddArc(x, y + height - d, d, d, 90, 90);
  path.CloseFigure();
}

}  // namespace

OverlayWindow* OverlayWindow::instance_ = nullptr;

OverlayWindow::OverlayWindow(std::function<void()> on_cancel)
    : on_cancel_(std::move(on_cancel)) {
  instance_ = this;

  Gdiplus::GdiplusStartupInput startup_input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &startup_input, nullptr);

  font_ = std::make_unique<Gdiplus::Font>(
      L"Microsoft JhengHei UI", static_cast<Gdiplus::REAL>(kFontSize),
      Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  if (font_->GetLastStatus() != Gdiplus::Ok) {
    font_ = std::make_unique<Gdiplus::Font>(
        Gdiplus::FontFamily::GenericSansSerif(),
        static_cast<Gdiplus::REAL>(kFontSize), Gdiplus::FontStyleBold,
        Gdiplus::UnitPixel);
  }

  HINSTANCE module = GetModuleHandle(nullptr);
  WNDCLASSEX window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = OverlayWindow::WndProc;
  window_class.hInstance = module;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClassName;
  RegisterClassEx(&window_class);

  hwnd_ = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWindowClassName, L"ZeroType Overlay", WS_POPUP, 0, 0, 1, 1, nullptr,
      nullptr, module, this);
}

OverlayWindow::~OverlayWindow() {
  RemoveEscHook();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  UnregisterClass(kWindowClassName, GetModuleHandle(nullptr));
  font_.reset();
  Gdiplus::GdiplusShutdown(gdiplus_token_);
  if (instance_ == this) instance_ = nullptr;
}

void OverlayWindow::Show(const std::string& status,
                         const std::string& message) {
  if (!hwnd_) return;

  status_ = status;
  message_ = Utf8ToWide(message);

  if (!visible_) {
    // Follow the monitor the user is working on, like NSScreen.main on macOS.
    HWND foreground = GetForegroundWindow();
    monitor_ = foreground
                   ? MonitorFromWindow(foreground, MONITOR_DEFAULTTOPRIMARY)
                   : MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
    scale_ = FlutterDesktopGetDpiForMonitor(monitor_) / 96.0;
    current_amplitude_ = 0.0;
    target_amplitude_ = 0.0;
  }

  ULONGLONG now = GetTickCount64();
  dot_dimmed_ = false;
  text_dot_count_ = 0;
  last_dot_tick_ = now;
  last_text_tick_ = now;
  last_frame_tick_ = now;

  Layout();
  Render();

  if (!visible_) {
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    SetTimer(hwnd_, kAnimationTimerId, kAnimationIntervalMs, nullptr);
    InstallEscHook();
    visible_ = true;
  }
  // Re-assert topmost in case another topmost window was raised meanwhile.
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void OverlayWindow::Hide() {
  if (!hwnd_ || !visible_) return;
  visible_ = false;
  KillTimer(hwnd_, kAnimationTimerId);
  RemoveEscHook();
  ShowWindow(hwnd_, SW_HIDE);
}

void OverlayWindow::UpdateAmplitude(double amplitude) {
  target_amplitude_ = amplitude;
}

void OverlayWindow::Layout() {
  Gdiplus::Bitmap measure_bitmap(1, 1, PixelFormat32bppPARGB);
  Gdiplus::Graphics measure(&measure_bitmap);
  measure.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
  Gdiplus::RectF bounds;
  measure.MeasureString(message_.c_str(), static_cast<INT>(message_.size()),
                        font_.get(), Gdiplus::PointF(0, 0),
                        Gdiplus::StringFormat::GenericTypographic(), &bounds);
  text_width_ = bounds.Width;

  // leading + dot + gap + text + [gap + waveform] + gap + X + trailing
  double width = kDotLeading + kDotSize + kGap + text_width_ + kCancelGap +
                 kCancelSize + kCancelTrailing;
  if (status_ == "recording") width += kGap + kWaveformWidth;
  // Reserve room for the animated "..." so the pill does not jump.
  if (HasTextAnimation()) width += kFontSize * 0.8;
  logical_width_ = std::max(kMinWidth, width);

  size_px_.cx = static_cast<LONG>(std::ceil(logical_width_ * scale_));
  size_px_.cy = static_cast<LONG>(std::ceil(kHeight * scale_));

  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfo(monitor_, &info);
  const RECT& work = info.rcWork;
  position_px_.x = work.left + ((work.right - work.left) - size_px_.cx) / 2;
  position_px_.y = work.bottom -
                   static_cast<LONG>(std::lround(kBottomOffset * scale_)) -
                   size_px_.cy;
}

void OverlayWindow::Render() {
  const int width = size_px_.cx;
  const int height = size_px_.cy;
  if (width <= 0 || height <= 0) return;

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;  // top-down
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  HDC screen_dc = GetDC(nullptr);
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS,
                                 &bits, nullptr, 0);
  if (dib && bits) {
    HGDIOBJ previous = SelectObject(memory_dc, dib);
    {
      // Premultiplied ARGB matches what UpdateLayeredWindow expects.
      Gdiplus::Bitmap bitmap(width, height, width * 4, PixelFormat32bppPARGB,
                             static_cast<BYTE*>(bits));
      Gdiplus::Graphics graphics(&bitmap);
      graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
      graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
      graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
      graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
      graphics.ScaleTransform(static_cast<Gdiplus::REAL>(scale_),
                              static_cast<Gdiplus::REAL>(scale_));
      Draw(graphics);
    }

    POINT source = {0, 0};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(hwnd_, screen_dc, &position_px_, &size_px_, memory_dc,
                        &source, 0, &blend, ULW_ALPHA);
    SelectObject(memory_dc, previous);
  }
  if (dib) DeleteObject(dib);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);
}

void OverlayWindow::Draw(Gdiplus::Graphics& graphics) {
  using Gdiplus::REAL;
  const Rgb color = ColorForStatus(status_);
  const REAL width = static_cast<REAL>(logical_width_);
  const REAL height = static_cast<REAL>(kHeight);
  const REAL center_y = height / 2;

  // Capsule background with a 1px status-colored border.
  {
    Gdiplus::GraphicsPath path;
    AddRoundedRect(path, 0.5f, 0.5f, width - 1, height - 1, (height - 1) / 2);
    Gdiplus::SolidBrush background(Gdiplus::Color(245, 13, 13, 13));
    graphics.FillPath(&background, &path);
    Gdiplus::Pen border(WithAlpha(color, 0.7), 1.0f);
    graphics.DrawPath(&border, &path);
  }

  // Status dot.
  {
    Gdiplus::SolidBrush dot(WithAlpha(color, dot_dimmed_ ? 0.3 : 1.0));
    const REAL size = static_cast<REAL>(kDotSize);
    graphics.FillEllipse(&dot, static_cast<REAL>(kDotLeading),
                         center_y - size / 2, size, size);
  }

  // Label, with animated dots while transcribing / cancelling.
  const REAL text_x = static_cast<REAL>(kDotLeading + kDotSize + kGap);
  {
    std::wstring text = message_;
    if (HasTextAnimation()) text.append(text_dot_count_, L'.');
    Gdiplus::StringFormat format(Gdiplus::StringFormat::GenericTypographic());
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    format.SetFormatFlags(format.GetFormatFlags() |
                          Gdiplus::StringFormatFlagsNoWrap);
    Gdiplus::SolidBrush brush(WithAlpha(color, 1.0));
    Gdiplus::RectF layout(text_x, 0, width - text_x, height);
    graphics.DrawString(text.c_str(), static_cast<INT>(text.size()),
                        font_.get(), layout, &format, &brush);
  }

  // Waveform, only while recording.
  if (status_ == "recording") {
    constexpr int kBars = 6;
    constexpr REAL kBarWidth = 3;
    constexpr REAL kSpacing = 3;
    const REAL total = kBars * (kBarWidth + kSpacing) - kSpacing;
    REAL x = text_x + static_cast<REAL>(text_width_ + kGap) +
             (static_cast<REAL>(kWaveformWidth) - total) / 2;
    Gdiplus::SolidBrush bar_brush(WithAlpha({255, 122, 0}, 0.85));
    for (int i = 0; i < kBars; ++i) {
      const double pulse = (std::sin(phase_ + i * 0.8) + 1) / 2;
      const REAL bar_height = static_cast<REAL>(
          std::min(kWaveformHeight,
                   std::max(3.0, pulse * current_amplitude_ * 18 + 3)));
      Gdiplus::GraphicsPath bar;
      AddRoundedRect(bar, x, center_y - bar_height / 2, kBarWidth, bar_height,
                     1.5f);
      graphics.FillPath(&bar_brush, &bar);
      x += kBarWidth + kSpacing;
    }
  }

  // Cancel (X in a circle), hidden while cancelling to avoid double triggers.
  if (status_ != "cancelling") {
    const REAL size = static_cast<REAL>(kCancelSize);
    const REAL cx = width - static_cast<REAL>(kCancelTrailing) - size / 2;
    const REAL radius = 7.0f;
    const REAL arm = 2.8f;
    Gdiplus::Pen pen(WithAlpha(color, 0.6), 1.4f);
    pen.SetStartCap(Gdiplus::LineCapRound);
    pen.SetEndCap(Gdiplus::LineCapRound);
    graphics.DrawEllipse(&pen, cx - radius, center_y - radius, radius * 2,
                         radius * 2);
    graphics.DrawLine(&pen, cx - arm, center_y - arm, cx + arm, center_y + arm);
    graphics.DrawLine(&pen, cx - arm, center_y + arm, cx + arm, center_y - arm);
  }
}

void OverlayWindow::Tick() {
  ULONGLONG now = GetTickCount64();
  bool dirty = false;

  if (HasDotAnimation() && now - last_dot_tick_ >= 600) {
    dot_dimmed_ = !dot_dimmed_;
    last_dot_tick_ = now;
    dirty = true;
  }
  if (HasTextAnimation() && now - last_text_tick_ >= 400) {
    text_dot_count_ = (text_dot_count_ + 1) % 4;
    last_text_tick_ = now;
    dirty = true;
  }
  if (status_ == "recording") {
    // Smooth toward the latest amplitude; louder input oscillates faster.
    current_amplitude_ += (target_amplitude_ - current_amplitude_) * 0.15;
    if (std::abs(target_amplitude_ - current_amplitude_) < 0.001) {
      current_amplitude_ = target_amplitude_;
    }
    const double elapsed =
        std::min(0.1, static_cast<double>(now - last_frame_tick_) / 1000.0);
    phase_ += elapsed * (3.5 + current_amplitude_ * 8.0);
    dirty = true;
  }
  last_frame_tick_ = now;

  if (dirty) Render();
}

bool OverlayWindow::HitTestCancel(LPARAM lparam) const {
  if (status_ == "cancelling") return false;
  const double x = static_cast<short>(LOWORD(lparam)) / scale_;
  const double y = static_cast<short>(HIWORD(lparam)) / scale_;
  // Slightly larger than the drawn icon to make it easier to hit.
  const double right = logical_width_ - kCancelTrailing + 4;
  const double left = right - kCancelSize - 8;
  const double top = (kHeight - kCancelSize) / 2 - 4;
  const double bottom = top + kCancelSize + 8;
  return x >= left && x <= right && y >= top && y <= bottom;
}

bool OverlayWindow::HasDotAnimation() const {
  return status_ == "recording" || status_ == "saving" ||
         status_ == "cancelling";
}

bool OverlayWindow::HasTextAnimation() const {
  return status_ == "transcribing" || status_ == "cancelling";
}

void OverlayWindow::InstallEscHook() {
  if (esc_hook_) return;
  esc_down_ = false;
  // Low-level hook so ESC works while another app has focus.
  esc_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, OverlayWindow::KeyboardHookProc,
                               GetModuleHandle(nullptr), 0);
}

void OverlayWindow::RemoveEscHook() {
  if (!esc_hook_) return;
  UnhookWindowsHookEx(esc_hook_);
  esc_hook_ = nullptr;
}

// static
LRESULT CALLBACK OverlayWindow::KeyboardHookProc(int code, WPARAM wparam,
                                                 LPARAM lparam) {
  if (code == HC_ACTION && instance_) {
    const auto* key = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    if (key->vkCode == VK_ESCAPE) {
      if (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN) {
        // Ignore auto-repeat so holding ESC cancels only once.
        if (!instance_->esc_down_) {
          instance_->esc_down_ = true;
          PostMessage(instance_->hwnd_, kEscCancelMessage, 0, 0);
        }
      } else {
        instance_->esc_down_ = false;
      }
    }
  }
  // Do not swallow ESC; the focused app still receives it.
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

// static
LRESULT CALLBACK OverlayWindow::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    auto* self = static_cast<OverlayWindow*>(create->lpCreateParams);
    self->hwnd_ = hwnd;
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else if (auto* self = reinterpret_cast<OverlayWindow*>(
                 GetWindowLongPtr(hwnd, GWLP_USERDATA))) {
    return self->HandleMessage(message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT OverlayWindow::HandleMessage(UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // Clicking the overlay must never steal focus from the target app.
      return MA_NOACTIVATE;
    case WM_SETCURSOR: {
      POINT cursor;
      GetCursorPos(&cursor);
      ScreenToClient(hwnd_, &cursor);
      bool over_cancel = HitTestCancel(MAKELPARAM(cursor.x, cursor.y));
      SetCursor(LoadCursor(nullptr, over_cancel ? IDC_HAND : IDC_ARROW));
      return TRUE;
    }
    case WM_LBUTTONUP:
      if (visible_ && HitTestCancel(lparam) && on_cancel_) on_cancel_();
      return 0;
    case WM_TIMER:
      if (wparam == kAnimationTimerId) Tick();
      return 0;
    case kEscCancelMessage:
      if (visible_ && on_cancel_) on_cancel_();
      return 0;
  }
  return DefWindowProc(hwnd_, message, wparam, lparam);
}
