#include "windows_update_http.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>

namespace {
struct HandleCloser {
  void operator()(void* handle) const {
    if (handle) WinHttpCloseHandle(handle);
  }
};
using HttpHandle = std::unique_ptr<void, HandleCloser>;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        utf8.data(), static_cast<int>(utf8.size()),
                                        nullptr, 0);
  if (!count) throw std::runtime_error("Invalid update URL or path encoding");
  std::wstring result(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                      static_cast<int>(utf8.size()), result.data(), count);
  return result;
}

void Check(bool ok, const char* operation) {
  if (!ok) {
    if (GetLastError() == ERROR_WINHTTP_SECURE_FAILURE) {
      throw std::runtime_error(
          "Windows no pudo validar el certificado HTTPS. Revisa fecha y hora, "
          "certificados raiz de Windows y el proxy o antivirus de la red.");
    }
    throw std::runtime_error(std::string(operation) + " (Windows " +
                             std::to_string(GetLastError()) + ")");
  }
}

struct Address {
  std::wstring host;
  std::wstring path;
};

Address ParseAddress(const std::wstring& url, bool redirect) {
  URL_COMPONENTS parts{};
  parts.dwStructSize = sizeof(parts);
  parts.dwSchemeLength = static_cast<DWORD>(-1);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  parts.dwUrlPathLength = static_cast<DWORD>(-1);
  parts.dwExtraInfoLength = static_cast<DWORD>(-1);
  parts.dwUserNameLength = static_cast<DWORD>(-1);
  parts.dwPasswordLength = static_cast<DWORD>(-1);
  Check(WinHttpCrackUrl(url.c_str(), 0, 0, &parts), "Invalid update URL");
  if (parts.nScheme != INTERNET_SCHEME_HTTPS || parts.nPort != 443 ||
      parts.dwUserNameLength || parts.dwPasswordLength) {
    throw std::runtime_error("Update URL must be HTTPS without credentials");
  }
  std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::transform(host.begin(), host.end(), host.begin(), ::towlower);
  const bool allowed = host == L"github.com" ||
                       (redirect && (host == L"release-assets.githubusercontent.com" ||
                                     host == L"objects.githubusercontent.com"));
  if (!allowed) throw std::runtime_error("Update redirect host is not allowed");
  std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength);
  if (host == L"github.com" &&
      path.find(L"/Corredora-Online/GW-Totem-s/releases/") != 0) {
    throw std::runtime_error("Update URL is outside the expected repository");
  }
  if (parts.dwExtraInfoLength) {
    path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }
  return {host, path};
}

std::wstring Location(HINTERNET request) {
  DWORD size = 0;
  WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION, WINHTTP_HEADER_NAME_BY_INDEX,
                      nullptr, &size, WINHTTP_NO_HEADER_INDEX);
  if (!size || GetLastError() != ERROR_INSUFFICIENT_BUFFER || size > 8192) {
    throw std::runtime_error("Update redirect has no valid destination");
  }
  std::wstring value(size / sizeof(wchar_t), L'\0');
  Check(WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION,
                            WINHTTP_HEADER_NAME_BY_INDEX, value.data(), &size,
                            WINHTTP_NO_HEADER_INDEX), "Read update redirect");
  value.resize(wcslen(value.c_str()));
  return value;
}
}  // namespace

UpdateHttpResponse FetchUpdate(const std::string& url, const std::string& path,
                               int64_t max_bytes) {
  if (max_bytes < 1 || max_bytes > 350LL * 1024 * 1024) {
    throw std::runtime_error("Invalid update size limit");
  }
  HttpHandle session(WinHttpOpen(L"Gour-net Kiosk Updater/1.0",
                                 WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                 WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
  Check(session != nullptr, "Start Windows HTTPS");
  Check(WinHttpSetTimeouts(session.get(), 25000, 25000, 25000, 45000),
        "Configure Windows HTTPS timeouts");

  std::wstring target = Wide(url);
  for (int redirects = 0; redirects < 6; ++redirects) {
    const Address address = ParseAddress(target, redirects > 0);
    HttpHandle connection(WinHttpConnect(session.get(), address.host.c_str(),
                                          INTERNET_DEFAULT_HTTPS_PORT, 0));
    Check(connection != nullptr, "Connect to update host");
    HttpHandle request(WinHttpOpenRequest(connection.get(), L"GET",
                                           address.path.c_str(), nullptr,
                                           WINHTTP_NO_REFERER,
                                           WINHTTP_DEFAULT_ACCEPT_TYPES,
                                           WINHTTP_FLAG_SECURE));
    Check(request != nullptr, "Open update request");
    DWORD disable = WINHTTP_DISABLE_REDIRECTS;
    Check(WinHttpSetOption(request.get(), WINHTTP_OPTION_DISABLE_FEATURE,
                           &disable, sizeof(disable)), "Limit update redirects");
    Check(WinHttpSendRequest(request.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                             WINHTTP_NO_REQUEST_DATA, 0, 0, 0),
          "Send update request");
    Check(WinHttpReceiveResponse(request.get(), nullptr), "Receive update response");

    DWORD status = 0;
    DWORD size = sizeof(status);
    Check(WinHttpQueryHeaders(request.get(),
                              WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                              WINHTTP_HEADER_NAME_BY_INDEX, &status, &size,
                              WINHTTP_NO_HEADER_INDEX), "Read update status");
    if (status == 301 || status == 302 || status == 303 || status == 307 ||
        status == 308) {
      const std::wstring location = Location(request.get());
      if (location.rfind(L"https://", 0) == 0) {
        target = location;
      } else if (location.rfind(L"/", 0) == 0 &&
                 location.rfind(L"//", 0) != 0) {
        target = L"https://" + address.host + location;
      } else {
        throw std::runtime_error("Update redirect is not an HTTPS URL");
      }
      continue;
    }
    UpdateHttpResponse response{static_cast<int>(status), {}};
    if (status != 200) return response;
    std::ofstream output;
    if (!path.empty()) {
      output.open(std::filesystem::path(Wide(path)), std::ios::binary | std::ios::trunc);
      if (!output) throw std::runtime_error("Cannot create update download");
    }
    std::array<uint8_t, 32768> buffer{};
    int64_t total = 0;
    while (true) {
      DWORD count = 0;
      Check(WinHttpReadData(request.get(), buffer.data(),
                            static_cast<DWORD>(buffer.size()), &count),
            "Read update body");
      if (!count) break;
      total += count;
      if (total > max_bytes) throw std::runtime_error("Update exceeds size limit");
      if (path.empty()) {
        response.bytes.insert(response.bytes.end(), buffer.begin(),
                              buffer.begin() + count);
      } else {
        output.write(reinterpret_cast<const char*>(buffer.data()), count);
        if (!output) throw std::runtime_error("Cannot save update download");
      }
    }
    if (output.is_open()) {
      output.close();
      if (!output) throw std::runtime_error("Cannot finish update download");
    }
    return response;
  }
  throw std::runtime_error("Too many update redirects");
}
