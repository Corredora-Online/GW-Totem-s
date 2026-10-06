#include "windows_hardware_bridge.h"

#include <flutter/standard_method_codec.h>
#include <devguid.h>
#include <setupapi.h>
#include <winspool.h>
#include <shellapi.h>
#include <filesystem>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <cwctype>
#include <deque>
#include <sstream>
#include <utility>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;

std::string Argument(const Value* arguments, const char* name) {
  const auto* map = arguments ? std::get_if<Map>(arguments) : nullptr;
  if (!map) return {};
  const auto found = map->find(Value(name));
  if (found == map->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

Map SaleResult(const std::string& response, bool delivered,
               const std::string& message) {
  return {{Value("response"), Value(response)},
          {Value("delivered"), Value(delivered)},
          {Value("message"), Value(message)}};
}

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                      static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring value(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      value.data(), size);
  return value;
}

std::string OemText(const std::string& utf8) {
  const std::wstring wide = Wide(utf8);
  if (wide.empty()) return {};
  const int size = WideCharToMultiByte(850, 0, wide.data(),
                                      static_cast<int>(wide.size()), nullptr, 0,
                                      "?", nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(850, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), size, "?", nullptr);
  return result;
}

std::wstring AutoDetectPaxPort() {
  HDEVINFO devices = SetupDiGetClassDevsW(&GUID_DEVCLASS_PORTS, nullptr,
                                           nullptr, DIGCF_PRESENT);
  if (devices == INVALID_HANDLE_VALUE) return {};
  std::wstring port;
  for (DWORD index = 0; ; ++index) {
    SP_DEVINFO_DATA info{};
    info.cbSize = static_cast<DWORD>(sizeof(info));
    if (!SetupDiEnumDeviceInfo(devices, index, &info)) break;
    wchar_t hardware[1024]{};
    if (!SetupDiGetDeviceRegistryPropertyW(devices, &info, SPDRP_HARDWAREID,
                                           nullptr,
                                           reinterpret_cast<PBYTE>(hardware),
                                           static_cast<DWORD>(sizeof(hardware)),
                                           nullptr)) continue;
    std::wstring id(hardware);
    std::transform(id.begin(), id.end(), id.begin(),
                   [](wchar_t ch) { return static_cast<wchar_t>(std::towupper(ch)); });
    if (id.find(L"VID_2FB8&PID_225E") == std::wstring::npos) continue;
    wchar_t friendly[1024]{};
    if (!SetupDiGetDeviceRegistryPropertyW(devices, &info, SPDRP_FRIENDLYNAME,
                                           nullptr,
                                           reinterpret_cast<PBYTE>(friendly),
                                           static_cast<DWORD>(sizeof(friendly)),
                                           nullptr)) continue;
    const std::wstring name(friendly);
    const auto start = name.rfind(L"(COM");
    const auto end = name.find(L')', start);
    if (start != std::wstring::npos && end != std::wstring::npos) {
      port = name.substr(start + 1, end - start - 1);
      break;
    }
  }
  SetupDiDestroyDeviceInfoList(devices);
  return port;
}

std::wstring ResolvePort(const std::string& requested) {
  if (requested.empty()) return AutoDetectPaxPort();
  std::wstring port = Wide(requested);
  std::transform(port.begin(), port.end(), port.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(std::towupper(ch)); });
  // Never allow an arbitrary file or device path through the serial setting.
  if (port.size() < 4 || port.substr(0, 3) != L"COM" ||
      !std::all_of(port.begin() + 3, port.end(),
                   [](wchar_t ch) { return ch >= L'0' && ch <= L'9'; })) return {};
  return port;
}

bool WriteAll(HANDLE handle, const std::string& bytes) {
  size_t position = 0;
  while (position < bytes.size()) {
    DWORD written = 0;
    if (!WriteFile(handle, bytes.data() + position,
                   static_cast<DWORD>(bytes.size() - position), &written,
                   nullptr) || written == 0) return false;
    position += written;
  }
  return true;
}

class JsonFramer {
 public:
  void Append(const char* bytes, DWORD length) {
    for (DWORD i = 0; i < length; ++i) {
      const char ch = bytes[i];
      if (depth_ == 0) {
        if (ch != '{') continue;
        current_.clear();
      }
      current_ += ch;
      if (quoted_) {
        if (escaped_) escaped_ = false;
        else if (ch == '\\') escaped_ = true;
        else if (ch == '"') quoted_ = false;
      } else if (ch == '"') {
        quoted_ = true;
      } else if (ch == '{') {
        ++depth_;
      } else if (ch == '}') {
        --depth_;
        if (depth_ == 0) {
          complete_.push_back(current_);
          current_.clear();
        }
      }
      if (current_.size() > 1024 * 1024) {
        current_.clear();
        depth_ = 0;
        quoted_ = false;
      }
    }
  }

  bool Take(std::string* value) {
    if (complete_.empty()) return false;
    *value = std::move(complete_.front());
    complete_.pop_front();
    return true;
  }

 private:
  std::string current_;
  std::deque<std::string> complete_;
  int depth_ = 0;
  bool quoted_ = false;
  bool escaped_ = false;
};

int FunctionCode(const std::string& message) {
  const auto key = message.find("FunctionCode");
  if (key == std::string::npos) return -1;
  const auto colon = message.find(':', key);
  if (colon == std::string::npos) return -1;
  size_t cursor = colon + 1;
  while (cursor < message.size() &&
         !std::isdigit(static_cast<unsigned char>(message[cursor]))) ++cursor;
  return cursor < message.size() ? std::atoi(message.c_str() + cursor) : -1;
}

Map PrintReceipt(const Value* args) {
  const std::string selected = Argument(args, "printerName");
  if (selected.empty()) {
    return {{Value("success"), Value(false)},
            {Value("message"), Value("Configura el nombre de la impresora termica en Windows.")}};
  }
  HANDLE printer = nullptr;
  std::wstring name = Wide(selected);
  if (!OpenPrinterW(name.data(), &printer, nullptr)) {
    return {{Value("success"), Value(false)},
            {Value("message"), Value("Windows no pudo abrir la impresora configurada.")}};
  }
  DWORD needed = 0;
  GetPrinterW(printer, 2, nullptr, 0, &needed);
  if (needed > 0) {
    std::vector<BYTE> info(needed);
    if (GetPrinterW(printer, 2, info.data(), needed, &needed)) {
      const auto* state = reinterpret_cast<const PRINTER_INFO_2W*>(info.data());
      if ((state->Status & (PRINTER_STATUS_OFFLINE | PRINTER_STATUS_PAPER_OUT |
                            PRINTER_STATUS_ERROR)) != 0) {
        ClosePrinter(printer);
        return {{Value("success"), Value(false)},
                {Value("message"), Value("La impresora esta sin papel, fuera de linea o en error.")}};
      }
    }
  }
  const std::string header = Argument(args, "header");
  const std::string number = Argument(args, "orderNumber");
  const std::string body = Argument(args, "body");
  const std::string footer = Argument(args, "footer");
  // ESC/POS, code page 850. Queue the entire receipt as one RAW spool job.
  std::string bytes("\x1B\x40\x1B\x74\x02\x1B\x61\x01", 8);
  bytes += OemText(header + "\n\n");
  bytes.append("\x1D\x21\x22", 3);
  bytes += OemText(number + "\n");
  bytes.append("\x1D\x21\x00\n\x1B\x61\x00", 7);
  bytes += OemText(body);
  bytes.append("\n\x1B\x61\x01", 4);
  bytes += OemText(footer + "\n\n\n");
  bytes.append("\x1D\x56\x00", 3);
  DOC_INFO_1W document{};
  document.pDocName = const_cast<LPWSTR>(L"Gour-net comprobante de pedido");
  document.pDatatype = const_cast<LPWSTR>(L"RAW");
  bool success = false;
  if (StartDocPrinterW(printer, 1, reinterpret_cast<LPBYTE>(&document))) {
    if (StartPagePrinter(printer)) {
      DWORD written = 0;
      success = WritePrinter(printer, const_cast<char*>(bytes.data()),
                             static_cast<DWORD>(bytes.size()), &written) &&
                static_cast<size_t>(written) == bytes.size();
      EndPagePrinter(printer);
    }
    EndDocPrinter(printer);
  }
  ClosePrinter(printer);
  return {{Value("success"), Value(success)},
          {Value("message"), Value(success ? "Enviado a la cola de impresion; confirma salida fisica."
                                             : "Windows no pudo enviar el comprobante ESC/POS.")}};
}
}  // namespace

WindowsHardwareBridge::WindowsHardwareBridge(flutter::FlutterEngine* engine,
                                             HWND window)
    : window_(window) {
  RegisterChannels(engine);
}

WindowsHardwareBridge::~WindowsHardwareBridge() {
  stopping_ = true;
  if (sale_worker_.joinable()) sale_worker_.join();
}

void WindowsHardwareBridge::PostUi(std::function<void()> callback) {
  {
    std::lock_guard<std::mutex> lock(callbacks_mutex_);
    callbacks_.push_back(std::move(callback));
  }
  PostMessageW(window_, kDispatchMessage, 0, 0);
}

void WindowsHardwareBridge::DispatchPending() {
  std::vector<std::function<void()>> callbacks;
  {
    std::lock_guard<std::mutex> lock(callbacks_mutex_);
    callbacks.swap(callbacks_);
  }
  for (auto& callback : callbacks) callback();
}

void WindowsHardwareBridge::RegisterChannels(flutter::FlutterEngine* engine) {
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();
  update_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      engine->messenger(), "cl.gournet.kiosk/updates", codec);
  update_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
        if (call.method_name() != "installUpdate") { result->NotImplemented(); return; }
        if (sale_active_) { result->Error("PAYMENT_ACTIVE", "Hay un pago activo"); return; }
        wchar_t module[MAX_PATH]{};
        GetModuleFileNameW(nullptr, module, MAX_PATH);
        const auto install_dir = std::filesystem::path(module).parent_path();
        if (!std::filesystem::exists(install_dir / L"gournet-managed-install.txt")) {
          result->Error("MANUAL_INSTALL_REQUIRED", "Instala primero el Setup de Gour-net (no la versión portátil)"); return;
        }
        const auto path = Wide(Argument(call.arguments(), "path"));
        if (path.empty() || std::filesystem::path(path).extension() != L".exe" ||
            GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
          result->Error("INVALID_UPDATE", "Instalador no encontrado"); return;
        }
        SHELLEXECUTEINFOW info{};
        info.cbSize = sizeof(info);
        info.fMask = SEE_MASK_NOCLOSEPROCESS;
        info.lpFile = path.c_str();
        info.lpParameters = L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-";
        info.nShow = SW_HIDE;
        if (!ShellExecuteExW(&info)) { result->Error("INSTALL_FAILED", "No se pudo iniciar el instalador"); return; }
        if (info.hProcess) CloseHandle(info.hProcess);
        result->Success(Value(true));
        PostMessageW(window_, kAdminExitMessage, 0, 0);
      });
  payment_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      engine->messenger(), "cl.gournet.kiosk/getnet", codec);
  payment_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call,
             std::unique_ptr<Result> result) {
        if (call.method_name() == "sale") {
          if (sale_active_.exchange(true)) {
            result->Success(Value(SaleResult("", true,
                "Ya existe una venta activa; concilia antes de reintentar.")));
            return;
          }
          const std::string payload = Argument(call.arguments(), "payload");
          const std::string port = Argument(call.arguments(), "port");
          if (payload.empty()) {
            sale_active_ = false;
            result->Success(Value(SaleResult("", false, "Falta el comando Getnet.")));
            return;
          }
          if (sale_worker_.joinable()) sale_worker_.join();
          std::shared_ptr<Result> pending(std::move(result));
          sale_worker_ = std::thread([this, payload, port, pending]() {
            RunSale(payload, port, pending);
          });
        } else if (call.method_name() == "cancelSale") {
          const std::string payload = Argument(call.arguments(), "payload");
          bool accepted = false;
          {
            std::lock_guard<std::mutex> lock(write_mutex_);
            HANDLE active = active_port_.load();
            if (active != INVALID_HANDLE_VALUE && !payload.empty()) {
              accepted = WriteAll(active, payload);
            }
          }
          result->Success(Value(Map{{Value("accepted"), Value(accepted)},
              {Value("message"), Value(accepted
                  ? "Cancelacion enviada al POS; espera su resultado final."
                  : "No hay una venta POS activa para cancelar.")}}));
        } else {
          result->NotImplemented();
        }
      });

  printer_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      engine->messenger(), "cl.gournet.kiosk/printer", codec);
  printer_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<Value>& call,
         std::unique_ptr<Result> result) {
        if (call.method_name() == "printReceipt") {
          result->Success(Value(PrintReceipt(call.arguments())));
        } else {
          result->NotImplemented();
        }
      });

  device_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      engine->messenger(), "cl.gournet.kiosk/device", codec);
  device_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call,
             std::unique_ptr<Result> result) {
        if (call.method_name() == "setKioskEnabled") {
          const auto* enabled = call.arguments()
              ? std::get_if<bool>(call.arguments()) : nullptr;
          SetFullscreen(enabled && *enabled);
          result->Success(Value(true));
        } else if (call.method_name() == "getKioskStatus") {
          result->Success(Value(Map{
              {Value("locked"), Value(kiosk_enabled_)},
              {Value("deviceOwner"), Value(false)},
              {Value("lockTaskPermitted"), Value(false)}}));
        } else if (call.method_name() == "exitKiosk") {
          SetFullscreen(false);
          result->Success(Value(true));
          PostMessageW(window_, kAdminExitMessage, 0, 0);
        } else {
          result->NotImplemented();
        }
      });
}

void WindowsHardwareBridge::SetFullscreen(bool enabled) {
  if (enabled == kiosk_enabled_) return;
  if (enabled) {
    original_style_ = static_cast<DWORD>(GetWindowLongPtrW(window_, GWL_STYLE));
    GetWindowRect(window_, &original_rect_);
    MONITORINFO monitor{};
    monitor.cbSize = static_cast<DWORD>(sizeof(monitor));
    GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor);
    SetWindowLongPtrW(window_, GWL_STYLE, WS_POPUP | WS_VISIBLE);
    const RECT& rect = monitor.rcMonitor;
    SetWindowPos(window_, HWND_TOPMOST, rect.left, rect.top,
                 rect.right - rect.left, rect.bottom - rect.top,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    kiosk_enabled_ = true;
  } else {
    kiosk_enabled_ = false;
    SetWindowLongPtrW(window_, GWL_STYLE, original_style_);
    SetWindowPos(window_, HWND_NOTOPMOST, original_rect_.left,
                 original_rect_.top, original_rect_.right - original_rect_.left,
                 original_rect_.bottom - original_rect_.top,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }
}

void WindowsHardwareBridge::RunSale(
    std::string payload, std::string requested_port,
    std::shared_ptr<Result> result) {
  std::string response;
  std::string message;
  bool delivered = false;
  const std::wstring port = ResolvePort(requested_port);
  HANDLE handle = INVALID_HANDLE_VALUE;
  if (port.empty()) {
    message = requested_port.empty()
        ? "No se detecto el puerto COM PAX. Configuralo manualmente."
        : "El puerto configurado debe tener formato COM seguido de numeros.";
  } else {
    handle = CreateFileW((L"\\\\.\\" + port).c_str(),
                         GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                         OPEN_EXISTING, 0, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
      message = "No se pudo abrir el puerto COM del IM30.";
    } else {
      DCB dcb{};
      dcb.DCBlength = static_cast<DWORD>(sizeof(dcb));
      if (!GetCommState(handle, &dcb)) {
        message = "No se pudo leer la configuracion del puerto COM.";
      } else {
        dcb.BaudRate = CBR_115200;
        dcb.ByteSize = 8;
        dcb.Parity = NOPARITY;
        dcb.StopBits = ONESTOPBIT;
        dcb.fBinary = TRUE;
        dcb.fOutxCtsFlow = FALSE;
        dcb.fOutxDsrFlow = FALSE;
        dcb.fDsrSensitivity = FALSE;
        dcb.fOutX = FALSE;
        dcb.fInX = FALSE;
        dcb.fDtrControl = DTR_CONTROL_ENABLE;
        dcb.fRtsControl = RTS_CONTROL_ENABLE;
        COMMTIMEOUTS timeouts{};
        timeouts.ReadIntervalTimeout = 1000;
        timeouts.ReadTotalTimeoutConstant = 1000;
        timeouts.WriteTotalTimeoutConstant = 3000;
        if (!SetCommState(handle, &dcb) || !SetCommTimeouts(handle, &timeouts)) {
          message = "No se pudo configurar Getnet a 115200 8N1.";
        } else {
          PurgeComm(handle, PURGE_RXCLEAR);
          {
            std::lock_guard<std::mutex> lock(write_mutex_);
            active_port_ = handle;
            // A partial write is still potentially chargeable.
            delivered = true;
            if (!WriteAll(handle, payload)) {
              message = "Fallo el envio al POS; el resultado requiere conciliacion.";
            }
          }
          if (message.empty()) {
            JsonFramer framer;
            const auto start = std::chrono::steady_clock::now();
            const auto deadline = start + std::chrono::seconds(125);
            bool acknowledged = false;
            char buffer[8192];
            while (!stopping_ && std::chrono::steady_clock::now() < deadline) {
              DWORD read = 0;
              if (!ReadFile(handle, buffer,
                            static_cast<DWORD>(sizeof(buffer)), &read, nullptr)) {
                message = "Error al leer el resultado del POS; requiere conciliacion.";
                break;
              }
              if (read > 0) {
                framer.Append(buffer, read);
                std::string frame;
                while (framer.Take(&frame)) {
                  if (frame.find("\"Received\"") != std::string::npos) {
                    acknowledged = true;
                    continue;
                  }
                  if (frame.find("JsonSerialized") == std::string::npos) continue;
                  {
                    std::lock_guard<std::mutex> lock(write_mutex_);
                    WriteAll(handle, "{\"Received\":true}");
                  }
                  if (FunctionCode(frame) == 100) {
                    response = frame;
                    break;
                  }
                }
                if (!response.empty()) break;
              }
              if (!acknowledged &&
                  std::chrono::steady_clock::now() - start >
                      std::chrono::seconds(5)) {
                message = "El POS no confirmo recepcion; revisa la transaccion.";
                break;
              }
            }
            if (response.empty() && message.empty()) {
              message = "Sin resultado final del POS; requiere conciliacion.";
            }
          }
          {
            std::lock_guard<std::mutex> lock(write_mutex_);
            active_port_ = INVALID_HANDLE_VALUE;
          }
        }
      }
      CloseHandle(handle);
    }
  }
  sale_active_ = false;
  PostUi([result, response, delivered, message]() {
    result->Success(Value(SaleResult(response, delivered, message)));
  });
}
