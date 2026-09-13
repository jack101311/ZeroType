#include "channel_handler.h"

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>
#include <variant>

#include "overlay_window.h"

// Keep channels alive for the duration of the app
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_keyboard_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_permission_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_overlay_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_control_channel;
// Raw pointer: destroyed in TeardownChannels() on the platform thread, never
// by static destructors (Dart's exit() may run those on another thread).
static OverlayWindow* g_overlay = nullptr;

// Simulates Ctrl+V (Windows paste shortcut) using Win32 SendInput.
// Equivalent to macOS CGEvent Cmd+V in AppDelegate.swift.
static void SimulatePaste() {
  INPUT inputs[4] = {};

  // Key down: Ctrl
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;

  // Key down: V
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';

  // Key up: V
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  // Key up: Ctrl
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  SendInput(4, inputs, sizeof(INPUT));
}

void SetupChannels(flutter::BinaryMessenger* messenger) {
  // ── Keyboard channel ────────────────────────────────────────────────────
  // Handles simulatePaste → Win32 SendInput Ctrl+V
  g_keyboard_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/keyboard",
          &flutter::StandardMethodCodec::GetInstance());

  g_keyboard_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "simulatePaste") {
          SimulatePaste();
          result->Success(nullptr);
        } else {
          result->NotImplemented();
        }
      });

  // ── Permission channel ──────────────────────────────────────────────────
  // Windows: SendInput does not require Accessibility permission.
  // Return true for checkAccessibility so the Settings page shows it as granted.
  g_permission_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/permission",
          &flutter::StandardMethodCodec::GetInstance());

  g_permission_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "checkAccessibility") {
          // No special permission required on Windows
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "openAccessibilitySettings") {
          // No-op on Windows
          result->Success(nullptr);
        } else {
          result->NotImplemented();
        }
      });

  // ── Control channel ─────────────────────────────────────────────────────
  // Native → Dart: "cancel" when the overlay X button or ESC is pressed.
  g_control_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/control",
          &flutter::StandardMethodCodec::GetInstance());

  // ── Overlay channel ─────────────────────────────────────────────────────
  // Floating always-on-top recording indicator (see overlay_window.h).
  g_overlay = new OverlayWindow([]() {
    if (g_control_channel) g_control_channel->InvokeMethod("cancel", nullptr);
  });

  g_overlay_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/overlay",
          &flutter::StandardMethodCodec::GetInstance());

  g_overlay_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        const std::string& method = call.method_name();
        if (method == "show") {
          std::string status = "recording";
          std::string message;
          if (args) {
            auto it = args->find(flutter::EncodableValue("status"));
            if (it != args->end()) {
              if (const auto* v = std::get_if<std::string>(&it->second)) {
                status = *v;
              }
            }
            it = args->find(flutter::EncodableValue("message"));
            if (it != args->end()) {
              if (const auto* v = std::get_if<std::string>(&it->second)) {
                message = *v;
              }
            }
          }
          if (g_overlay) g_overlay->Show(status, message);
          result->Success(nullptr);
        } else if (method == "hide") {
          if (g_overlay) g_overlay->Hide();
          result->Success(nullptr);
        } else if (method == "updateAmplitude") {
          double amplitude = 0.0;
          if (args) {
            auto it = args->find(flutter::EncodableValue("amplitude"));
            if (it != args->end()) {
              if (const auto* v = std::get_if<double>(&it->second)) {
                amplitude = *v;
              }
            }
          }
          if (g_overlay) g_overlay->UpdateAmplitude(amplitude);
          result->Success(nullptr);
        } else {
          result->NotImplemented();
        }
      });
}

void TeardownChannels() {
  delete g_overlay;
  g_overlay = nullptr;
  if (g_overlay_channel) g_overlay_channel->SetMethodCallHandler(nullptr);
}
