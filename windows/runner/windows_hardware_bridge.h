#ifndef RUNNER_WINDOWS_HARDWARE_BRIDGE_H_
#define RUNNER_WINDOWS_HARDWARE_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <windows.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Flutter method channels for the Windows COM POS, ESC/POS printer and window.
// The bank protocol is signed and verified in Dart; this class transports the
// exact bytes to and from the configured Windows devices.
class WindowsHardwareBridge {
 public:
  static constexpr UINT kDispatchMessage = WM_APP + 77;
  static constexpr UINT kAdminExitMessage = WM_APP + 78;

  WindowsHardwareBridge(flutter::FlutterEngine* engine, HWND window);
  ~WindowsHardwareBridge();

  WindowsHardwareBridge(const WindowsHardwareBridge&) = delete;
  WindowsHardwareBridge& operator=(const WindowsHardwareBridge&) = delete;

  void DispatchPending();
  bool kiosk_enabled() const { return kiosk_enabled_; }

 private:
  void RegisterChannels(flutter::FlutterEngine* engine);
  void SetFullscreen(bool enabled);
  void PostUi(std::function<void()> callback);
  void RunSale(std::string payload, std::string requested_port,
               std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_;
  bool kiosk_enabled_ = false;
  DWORD original_style_ = 0;
  RECT original_rect_{};

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      payment_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      printer_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      device_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> update_channel_;

  std::atomic<bool> stopping_{false};
  std::atomic<bool> sale_active_{false};
  std::atomic<HANDLE> active_port_{INVALID_HANDLE_VALUE};
  std::mutex write_mutex_;
  std::thread sale_worker_;

  std::mutex callbacks_mutex_;
  std::vector<std::function<void()>> callbacks_;
};

#endif  // RUNNER_WINDOWS_HARDWARE_BRIDGE_H_
