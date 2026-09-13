#ifndef RUNNER_OVERLAY_WINDOW_H_
#define RUNNER_OVERLAY_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

namespace Gdiplus {
class Font;
class Graphics;
}  // namespace Gdiplus

// Floating recording indicator shown above every other window without taking
// focus, so the simulated Ctrl+V still reaches the app the user is typing in.
// Equivalent to OverlayPanel in macos/Runner/AppDelegate.swift.
class OverlayWindow {
 public:
  // |on_cancel| runs on the platform thread when the X button or ESC is
  // pressed while the overlay is visible.
  explicit OverlayWindow(std::function<void()> on_cancel);
  ~OverlayWindow();

  OverlayWindow(const OverlayWindow&) = delete;
  OverlayWindow& operator=(const OverlayWindow&) = delete;

  // |status| is one of recording, cancelling, saving, transcribing, done,
  // error. |message| is UTF-8.
  void Show(const std::string& status, const std::string& message);
  void Hide();
  void UpdateAmplitude(double amplitude);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  static LRESULT CALLBACK KeyboardHookProc(int code, WPARAM wparam,
                                           LPARAM lparam);

  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void Layout();
  void Render();
  void Draw(Gdiplus::Graphics& graphics);
  void Tick();
  bool HitTestCancel(LPARAM lparam) const;
  void InstallEscHook();
  void RemoveEscHook();

  bool HasDotAnimation() const;
  bool HasTextAnimation() const;

  static OverlayWindow* instance_;

  std::function<void()> on_cancel_;
  ULONG_PTR gdiplus_token_ = 0;
  std::unique_ptr<Gdiplus::Font> font_;
  HWND hwnd_ = nullptr;
  HHOOK esc_hook_ = nullptr;
  bool esc_down_ = false;
  bool visible_ = false;

  std::string status_;
  std::wstring message_;

  // Geometry. Logical values are in 96-DPI pixels, matching macOS points.
  HMONITOR monitor_ = nullptr;
  double scale_ = 1.0;
  double logical_width_ = 0.0;
  double text_width_ = 0.0;
  SIZE size_px_ = {0, 0};
  POINT position_px_ = {0, 0};

  // Animation state.
  bool dot_dimmed_ = false;
  int text_dot_count_ = 0;
  ULONGLONG last_dot_tick_ = 0;
  ULONGLONG last_text_tick_ = 0;
  ULONGLONG last_frame_tick_ = 0;
  double current_amplitude_ = 0.0;
  double target_amplitude_ = 0.0;
  double phase_ = 0.0;
};

#endif  // RUNNER_OVERLAY_WINDOW_H_
