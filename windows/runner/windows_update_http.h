#ifndef RUNNER_WINDOWS_UPDATE_HTTP_H_
#define RUNNER_WINDOWS_UPDATE_HTTP_H_

#include <cstdint>
#include <string>
#include <vector>

struct UpdateHttpResponse {
  int status;
  std::vector<uint8_t> bytes;
};

// Uses Windows Schannel and its certificate/proxy configuration. Throws on
// network errors, invalid redirects, or responses over max_bytes.
UpdateHttpResponse FetchUpdate(const std::string& url, const std::string& path,
                               int64_t max_bytes);

#endif  // RUNNER_WINDOWS_UPDATE_HTTP_H_
