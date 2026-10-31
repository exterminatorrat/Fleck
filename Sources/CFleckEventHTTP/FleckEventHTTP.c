#include "FleckEventHTTP.h"

#include <arpa/inet.h>
#include <curl/curl.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
#include <stdatomic.h>
#include "FleckEventHTTPTestSupport.h"
#endif

#define FL_MAX_URL_BYTES 2048U
#define FL_MAX_HOST_BYTES 255U
#define FL_MAX_TARGET_BYTES 2048U
#define FL_MAX_REQUEST_BODY_BYTES 1024U
#define FL_MAX_HEADER_VALUE_BYTES 1024U
#define FL_MAX_REQUEST_HEADER_BYTES 2048U
#define FL_MAX_RESPONSE_HEADER_BYTES 16384U
#define FL_MAX_RESPONSE_BODY_BYTES 65536U
#define FL_MAX_RESPONSE_RETRY_AFTER_BYTES \
  ((size_t)FLECK_EVENT_HTTP_MAX_RETRY_AFTER_VALUE_BYTES)
#define FL_MAX_REQUEST_HEADERS 5U
#define FL_MAX_TIMEOUT_MS 10000U
#define FL_MAX_CONNECT_TIMEOUT_MS 3000U

struct fl_url_parts {
  char *scheme;
  char *host;
  char *port;
  char *path;
  char *query;
  char *request_target;
  uint16_t effective_port;
};

#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
struct fl_test_configuration {
  const char *certificate_path;
  const char *resolve_address;
  uint16_t loopback_port;
  uint32_t timeout_ms;
  uint32_t flags;
  void *cancellation_context;
  FleckEventHTTPCancellationCheck cancellation_check;
  FleckEventHTTPTestObservation *observation;
};
#endif

struct fl_request {
  const char *url;
  const char *host;
  uint16_t port;
  const char *request_target;
  const char *pinned_address;
  const uint8_t *body;
  size_t body_length;
  const FleckEventHTTPHeader *headers;
  size_t header_count;
  uint32_t timeout_ms;
  FleckEventHTTPCancellationCheck cancellation_check;
  void *cancellation_context;
  uint8_t *response_body;
  size_t response_body_capacity;
  size_t *response_body_length;
  int64_t *status_code;
  uint8_t *response_retry_after_value;
  size_t response_retry_after_value_capacity;
  size_t *response_retry_after_value_length;
};

struct fl_context {
  struct sockaddr_storage pin;
  socklen_t pin_length;
  int pin_family;
  uint16_t port;
  uint64_t deadline_ms;
  int clock_failed;
  int cancelled;
  size_t response_header_bytes;
  bool response_header_failed;
  bool response_header_block_open;
  bool response_header_block_is_final;
  bool response_final_block_started;
  bool response_final_block_ambiguous;
  bool response_retry_after_available;
  bool response_retry_after_invalid;
  bool response_retry_after_last_field;
  size_t response_retry_after_field_count;
  size_t response_retry_after_value_length;
  uint8_t response_retry_after_value[FL_MAX_RESPONSE_RETRY_AFTER_BYTES];
  bool response_body_started;
  size_t response_body_bytes;
  uint8_t *response_body;
  size_t response_body_capacity;
  FleckEventHTTPCancellationCheck cancellation_check;
  void *cancellation_context;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  struct fl_test_configuration *test;
  curl_socket_t test_socket;
#endif
};

static pthread_once_t fl_curl_once = PTHREAD_ONCE_INIT;
static CURLcode fl_curl_init_result = CURLE_FAILED_INIT;

static void fl_initialize_curl(void) {
  fl_curl_init_result = curl_global_init(CURL_GLOBAL_DEFAULT);
  if (fl_curl_init_result != CURLE_OK) return;
  const curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);
  if (version == NULL
      || (version->features & (int)CURL_VERSION_THREADSAFE) == 0)
    fl_curl_init_result = CURLE_FAILED_INIT;
}

static int fl_curl_runtime_ready(void) {
  return pthread_once(&fl_curl_once, fl_initialize_curl) == 0
      && fl_curl_init_result == CURLE_OK;
}

static int fl_ascii_string(const char *value, size_t maximum, size_t *length_out) {
  if (value == NULL) return 0;
  size_t length = strnlen(value, maximum + 1U);
  if (length == 0U || length > maximum) return 0;
  for (size_t index = 0U; index < length; index++) {
    unsigned char character = (unsigned char)value[index];
    if (character < 0x21U || character > 0x7eU) return 0;
  }
  if (length_out != NULL) *length_out = length;
  return 1;
}

static char *fl_copy_url_part(CURLU *url, CURLUPart part, unsigned int flags) {
  char *value = NULL;
  if (curl_url_get(url, part, &value, flags) != CURLUE_OK) return NULL;
  return value;
}

static void fl_free_url_parts(struct fl_url_parts *parts) {
  if (parts == NULL) return;
  curl_free(parts->scheme);
  curl_free(parts->host);
  curl_free(parts->port);
  curl_free(parts->path);
  curl_free(parts->query);
  free(parts->request_target);
  memset(parts, 0, sizeof(*parts));
}

static int fl_url_part_is_absent(CURLU *url, CURLUPart part, CURLUcode absent_code) {
  char *value = NULL;
  CURLUcode result = curl_url_get(url, part, &value, 0U);
  if (value != NULL) curl_free(value);
  return result == absent_code;
}

static int fl_parse_url(const char *value, struct fl_url_parts *parts) {
  if (parts == NULL) return 0;
  memset(parts, 0, sizeof(*parts));
  size_t url_length = 0U;
  if (!fl_ascii_string(value, FL_MAX_URL_BYTES, &url_length)
      || !fl_curl_runtime_ready()) return 0;

  CURLU *url = curl_url();
  if (url == NULL) return 0;
  CURLUcode result = curl_url_set(url, CURLUPART_URL, value, CURLU_PATH_AS_IS);
  if (result != CURLUE_OK) {
    curl_url_cleanup(url);
    return 0;
  }

  parts->scheme = fl_copy_url_part(url, CURLUPART_SCHEME, 0U);
  parts->host = fl_copy_url_part(url, CURLUPART_HOST, 0U);
  parts->port = fl_copy_url_part(url, CURLUPART_PORT, CURLU_DEFAULT_PORT);
  parts->path = fl_copy_url_part(url, CURLUPART_PATH, 0U);
  char *query = NULL;
  CURLUcode query_result = curl_url_get(url, CURLUPART_QUERY, &query, 0U);

  int safe = parts->scheme != NULL && parts->host != NULL && parts->port != NULL
      && parts->path != NULL
      && fl_url_part_is_absent(url, CURLUPART_USER, CURLUE_NO_USER)
      && fl_url_part_is_absent(url, CURLUPART_PASSWORD, CURLUE_NO_PASSWORD)
      && fl_url_part_is_absent(url, CURLUPART_FRAGMENT, CURLUE_NO_FRAGMENT)
      && (query_result == CURLUE_OK || query_result == CURLUE_NO_QUERY);
  if (!safe || strcmp(parts->scheme, "https") != 0) {
    if (query != NULL) curl_free(query);
    curl_url_cleanup(url);
    fl_free_url_parts(parts);
    return 0;
  }

  char *end = NULL;
  errno = 0;
  unsigned long port = strtoul(parts->port, &end, 10);
  if (errno != 0 || end == parts->port || *end != '\0' || port == 0UL || port > 65535UL) {
    if (query != NULL) curl_free(query);
    curl_url_cleanup(url);
    fl_free_url_parts(parts);
    return 0;
  }
  parts->effective_port = (uint16_t)port;

  size_t host_length = 0U;
  size_t path_length = 0U;
  size_t query_length = query == NULL ? 0U : strlen(query);
  if (!fl_ascii_string(parts->host, FL_MAX_HOST_BYTES, &host_length)
      || !fl_ascii_string(parts->path, FL_MAX_TARGET_BYTES, &path_length)
      || parts->path[0] != '/') {
    if (query != NULL) curl_free(query);
    curl_url_cleanup(url);
    fl_free_url_parts(parts);
    return 0;
  }

  size_t target_length = path_length + (query == NULL ? 0U : query_length + 1U);
  if (target_length == 0U || target_length > FL_MAX_TARGET_BYTES) {
    if (query != NULL) curl_free(query);
    curl_url_cleanup(url);
    fl_free_url_parts(parts);
    return 0;
  }
  parts->request_target = malloc(target_length + 1U);
  if (parts->request_target == NULL) {
    if (query != NULL) curl_free(query);
    curl_url_cleanup(url);
    fl_free_url_parts(parts);
    return 0;
  }
  memcpy(parts->request_target, parts->path, path_length);
  if (query != NULL) {
    parts->request_target[path_length] = '?';
    memcpy(parts->request_target + path_length + 1U, query, query_length);
  }
  parts->request_target[target_length] = '\0';

  size_t target_ascii_length = 0U;
  int target_safe = fl_ascii_string(parts->request_target, FL_MAX_TARGET_BYTES,
                                    &target_ascii_length);
  if (query != NULL) curl_free(query);
  curl_url_cleanup(url);
  if (!target_safe) {
    fl_free_url_parts(parts);
    return 0;
  }
  return 1;
}

static int fl_parts_match(
    const struct fl_url_parts *parts,
    const char *host,
    uint16_t port,
    const char *request_target) {
  size_t host_length = 0U;
  size_t target_length = 0U;
  return parts != NULL && host != NULL && request_target != NULL
      && port != 0U
      && fl_ascii_string(host, FL_MAX_HOST_BYTES, &host_length)
      && fl_ascii_string(request_target, FL_MAX_TARGET_BYTES, &target_length)
      && strcmp(parts->host, host) == 0
      && parts->effective_port == port
      && strcmp(parts->request_target, request_target) == 0;
}

static int fl_is_public_ipv4(const uint8_t *address) {
  uint8_t first = address[0];
  uint8_t second = address[1];
  uint8_t third = address[2];
  if (first == 0U || first == 10U || first == 127U || first >= 224U) return 0;
  if (first == 100U && second >= 64U && second <= 127U) return 0;
  if (first == 169U && second == 254U) return 0;
  if (first == 172U && second >= 16U && second <= 31U) return 0;
  if (first == 192U && second == 0U && (third == 0U || third == 2U)) return 0;
  if (first == 192U && second == 88U && third == 99U) return 0;
  if (first == 192U && second == 168U) return 0;
  if (first == 198U && (second == 18U || second == 19U)) return 0;
  if (first == 198U && second == 51U && third == 100U) return 0;
  if (first == 203U && second == 0U && third == 113U) return 0;
  return 1;
}

static int fl_is_public_ipv6(const uint8_t *address) {
  if ((address[0] & 0xe0U) != 0x20U) return 0;
  if (address[0] == 0x3fU && address[1] == 0xfeU) return 0;
  if (address[0] == 0x3fU && address[1] == 0xffU
      && (address[2] & 0xf0U) == 0U) return 0;
  if (address[0] == 0x20U && address[1] == 0x01U
      && address[2] < 0x02U) return 0;
  if (address[0] == 0x20U && address[1] == 0x01U
      && address[2] == 0x0dU && address[3] == 0xb8U) return 0;
  if (address[0] == 0x20U && address[1] == 0x02U) return 0;
  return 1;
}

int fleck_event_http_is_public_address(int family, const uint8_t *address, size_t length) {
  if (address == NULL) return 0;
  if (family == AF_INET) return length == 4U && fl_is_public_ipv4(address);
  if (family == AF_INET6) return length == 16U && fl_is_public_ipv6(address);
  return 0;
}

static int fl_public_pin(
    const char *address,
    uint16_t port,
    struct sockaddr_storage *storage,
    socklen_t *length,
    int *family_out) {
  if (address == NULL || storage == NULL || length == NULL || family_out == NULL || port == 0U)
    return 0;
  memset(storage, 0, sizeof(*storage));
  struct sockaddr_in *ipv4 = (struct sockaddr_in *)storage;
  if (inet_pton(AF_INET, address, &ipv4->sin_addr) == 1) {
    ipv4->sin_len = (uint8_t)sizeof(*ipv4);
    ipv4->sin_family = AF_INET;
    ipv4->sin_port = htons(port);
    if (!fleck_event_http_is_public_address(AF_INET,
        (const uint8_t *)&ipv4->sin_addr, sizeof(ipv4->sin_addr))) return 0;
    char canonical[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &ipv4->sin_addr, canonical, sizeof(canonical)) == NULL
        || strcmp(canonical, address) != 0) return 0;
    *length = (socklen_t)sizeof(*ipv4);
    *family_out = AF_INET;
    return 1;
  }

  memset(storage, 0, sizeof(*storage));
  struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)storage;
  if (inet_pton(AF_INET6, address, &ipv6->sin6_addr) != 1) return 0;
  ipv6->sin6_len = (uint8_t)sizeof(*ipv6);
  ipv6->sin6_family = AF_INET6;
  ipv6->sin6_port = htons(port);
  if (!fleck_event_http_is_public_address(AF_INET6,
      (const uint8_t *)&ipv6->sin6_addr, sizeof(ipv6->sin6_addr))) return 0;
  char canonical[INET6_ADDRSTRLEN];
  if (inet_ntop(AF_INET6, &ipv6->sin6_addr, canonical, sizeof(canonical)) == NULL
      || strcmp(canonical, address) != 0) return 0;
  *length = (socklen_t)sizeof(*ipv6);
  *family_out = AF_INET6;
  return 1;
}

static int fl_valid_webhook_id(const char *value) {
  size_t length = 0U;
  if (!fl_ascii_string(value, 128U, &length)) return 0;
  for (size_t index = 0U; index < length; index++) {
    unsigned char character = (unsigned char)value[index];
    if (!((character >= 'a' && character <= 'z')
          || (character >= 'A' && character <= 'Z')
          || (character >= '0' && character <= '9')
          || character == '_' || character == '-' || character == ':')) return 0;
  }
  return 1;
}

static int fl_valid_timestamp(const char *value) {
  size_t length = 0U;
  if (!fl_ascii_string(value, 19U, &length)) return 0;
  if (length > 1U && value[0] == '0') return 0;
  for (size_t index = 0U; index < length; index++) {
    if (value[index] < '0' || value[index] > '9') return 0;
  }
  errno = 0;
  char *end = NULL;
  unsigned long long number = strtoull(value, &end, 10);
  return errno == 0 && end != value && *end == '\0' && number <= (unsigned long long)INT64_MAX;
}

static int fl_valid_signature_part(const char *value) {
  if (memcmp(value, "v1,", 3U) != 0 || value[46] != '=') return 0;
  for (size_t index = 3U; index < 46U; index++) {
    unsigned char character = (unsigned char)value[index];
    int valid = (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || (character >= '0' && character <= '9')
        || character == '+' || character == '/';
    if (!valid) return 0;
  }
  return strchr("AEIMQUYcgkosw048", value[45]) != NULL;
}

static int fl_valid_signature(const char *value) {
  if (value == NULL) return 0;
  size_t length = strnlen(value, 96U);
  if ((length != 47U && length != 95U)
      || !fl_valid_signature_part(value)) return 0;
  return length == 47U
      || (value[47] == ' ' && fl_valid_signature_part(value + 48U));
}

static int fl_valid_subscription_id(const char *value) {
  size_t length = 0U;
  if (!fl_ascii_string(value, 68U, &length) || length != 68U
      || memcmp(value, "evt_", 4U) != 0) return 0;
  for (size_t index = 4U; index < length; index++) {
    unsigned char character = (unsigned char)value[index];
    int valid = (character >= 'a' && character <= 'f')
        || (character >= '0' && character <= '9');
    if (!valid) return 0;
  }
  return 1;
}

static int fl_validate_headers(const FleckEventHTTPHeader *headers, size_t count) {
  if (headers == NULL || count != FL_MAX_REQUEST_HEADERS) return 0;
  unsigned int seen = 0U;
  size_t total = 0U;
  for (size_t index = 0U; index < count; index++) {
    const char *name = headers[index].name;
    const char *value = headers[index].value;
    size_t name_length = 0U;
    size_t value_length = 0U;
    if (!fl_ascii_string(name, 32U, &name_length) || value == NULL) return 0;
    value_length = strnlen(value, FL_MAX_HEADER_VALUE_BYTES + 1U);
    if (value_length == 0U || value_length > FL_MAX_HEADER_VALUE_BYTES) return 0;
    for (size_t character_index = 0U; character_index < value_length; character_index++) {
      unsigned char character = (unsigned char)value[character_index];
      if (character < 0x20U || character > 0x7eU) return 0;
    }
    unsigned int bit = 0U;
    if (strcmp(name, "content-type") == 0) {
      bit = 1U;
      if (strcmp(value, "application/json") != 0) return 0;
    } else if (strcmp(name, "webhook-id") == 0) {
      bit = 2U;
      if (!fl_valid_webhook_id(value)) return 0;
    } else if (strcmp(name, "webhook-timestamp") == 0) {
      bit = 4U;
      if (!fl_valid_timestamp(value)) return 0;
    } else if (strcmp(name, "webhook-signature") == 0) {
      bit = 8U;
      if (!fl_valid_signature(value)) return 0;
    } else if (strcmp(name, "x-mcp-subscription-id") == 0) {
      bit = 16U;
      if (!fl_valid_subscription_id(value)) return 0;
    } else {
      return 0;
    }
    if ((seen & bit) != 0U) return 0;
    seen |= bit;
    if (value_length + name_length + 4U > FL_MAX_REQUEST_HEADER_BYTES - total) return 0;
    total += value_length + name_length + 4U;
    if (total > FL_MAX_REQUEST_HEADER_BYTES) return 0;
  }
  return seen == 31U;
}

static int fl_cancelled(struct fl_context *context) {
  if (context == NULL) return 1;
  if (context->cancellation_check != NULL
      && context->cancellation_check(context->cancellation_context) != 0) {
    context->cancelled = 1;
    return 1;
  }
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    context->clock_failed = 1;
    return 1;
  }
  uint64_t current_ms = (uint64_t)now.tv_sec * 1000U + (uint64_t)now.tv_nsec / 1000000U;
  return current_ms >= context->deadline_ms;
}

static int fl_remote_matches_pin(struct fl_context *context, const char *remote, int remote_port) {
  if (context == NULL || remote == NULL || remote_port != (int)context->port) return 0;
  if (context->pin_family == AF_INET) {
    struct in_addr address;
    return inet_pton(AF_INET, remote, &address) == 1
        && address.s_addr == ((const struct sockaddr_in *)&context->pin)->sin_addr.s_addr;
  }
  if (context->pin_family == AF_INET6) {
    struct in6_addr address;
    return inet_pton(AF_INET6, remote, &address) == 1
        && memcmp(&address,
            &((const struct sockaddr_in6 *)&context->pin)->sin6_addr,
            sizeof(address)) == 0;
  }
  return 0;
}

static int fl_destination_matches_pin(
    struct fl_context *context,
    curlsocktype purpose,
    const struct curl_sockaddr *address) {
  if (context == NULL || address == NULL || purpose != CURLSOCKTYPE_IPCXN
      || address->family != context->pin_family
      || address->socktype != SOCK_STREAM || address->protocol != IPPROTO_TCP
      || address->addrlen != context->pin_length) return 0;
  if (context->pin_family == AF_INET) {
    const struct sockaddr_in *attempt = (const struct sockaddr_in *)&address->addr;
    const struct sockaddr_in *pin = (const struct sockaddr_in *)&context->pin;
    if (attempt->sin_len != 0U && attempt->sin_len != sizeof(*attempt)) return 0;
    struct sockaddr_in normalized = *attempt;
    normalized.sin_len = (uint8_t)sizeof(normalized);
    return memcmp(&normalized, pin, sizeof(normalized)) == 0;
  }
  if (context->pin_family == AF_INET6) {
    const struct sockaddr_in6 *attempt = (const struct sockaddr_in6 *)&address->addr;
    const struct sockaddr_in6 *pin = (const struct sockaddr_in6 *)&context->pin;
    if (attempt->sin6_len != 0U && attempt->sin6_len != sizeof(*attempt)) return 0;
    struct sockaddr_in6 normalized = *attempt;
    normalized.sin6_len = (uint8_t)sizeof(normalized);
    return memcmp(&normalized, pin, sizeof(normalized)) == 0;
  }
  return 0;
}

static int fl_set_socket_no_sigpipe(curl_socket_t socket_fd) {
  int enabled = 1;
  return setsockopt(socket_fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                    (socklen_t)sizeof(enabled)) == 0;
}

static curl_socket_t fl_open_socket(
    void *userdata,
    curlsocktype purpose,
    struct curl_sockaddr *address) {
  struct fl_context *context = userdata;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (context != NULL && context->test != NULL && context->test->observation != NULL)
    context->test->observation->opensocket_calls++;
#endif
  if (!fl_destination_matches_pin(context, purpose, address)) {
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
    if (context != NULL && context->test != NULL && context->test->observation != NULL)
      context->test->observation->pin_rejected++;
#endif
    return CURL_SOCKET_BAD;
  }
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (context->test != NULL) {
    context->test->observation->pin_matches++;
    if (context->test->loopback_port == 0U) return CURL_SOCKET_BAD;
    curl_socket_t socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_fd == CURL_SOCKET_BAD) return CURL_SOCKET_BAD;
    context->test->observation->sockets_created++;
    if (!fl_set_socket_no_sigpipe(socket_fd)) {
      close(socket_fd);
      return CURL_SOCKET_BAD;
    }
    struct sockaddr_in loopback;
    memset(&loopback, 0, sizeof(loopback));
    loopback.sin_len = (uint8_t)sizeof(loopback);
    loopback.sin_family = AF_INET;
    loopback.sin_port = htons(context->test->loopback_port);
    loopback.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(socket_fd, (struct sockaddr *)&loopback, sizeof(loopback)) != 0) {
      close(socket_fd);
      return CURL_SOCKET_BAD;
    }
    context->test_socket = socket_fd;
    return socket_fd;
  }
#endif
  curl_socket_t socket_fd = socket(address->family, address->socktype, address->protocol);
  if (socket_fd == CURL_SOCKET_BAD) return CURL_SOCKET_BAD;
  if (!fl_set_socket_no_sigpipe(socket_fd)) {
    close(socket_fd);
    return CURL_SOCKET_BAD;
  }
  return socket_fd;
}

static int fl_socket_options(void *userdata, curl_socket_t socket, curlsocktype purpose) {
  struct fl_context *context = userdata;
  (void)purpose;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (context != NULL && context->test != NULL && socket == context->test_socket)
    return CURL_SOCKOPT_ALREADY_CONNECTED;
#else
  (void)context;
  (void)socket;
#endif
  return CURL_SOCKOPT_OK;
}

static int fl_prerequest(
    void *userdata,
    char *remote_ip,
    char *local_ip,
    int remote_port,
    int local_port) {
  struct fl_context *context = userdata;
  (void)local_ip;
  (void)local_port;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (context != NULL && context->test != NULL && context->test->observation != NULL)
    context->test->observation->pre_request_calls++;
  if (context != NULL && context->test != NULL
      && (context->test->flags & 2U) != 0U
      && context->test->cancellation_check != NULL) {
    FleckEventHTTPTestCancellationCancel(
        (FleckEventHTTPTestCancellation *)context->cancellation_context);
  }
#endif
  if (!fl_remote_matches_pin(context, remote_ip, remote_port)) {
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
    if (context != NULL && context->test != NULL && context->test->observation != NULL)
      context->test->observation->pin_rejected++;
#endif
    return CURL_PREREQFUNC_ABORT;
  }
  return fl_cancelled(context) ? CURL_PREREQFUNC_ABORT : CURL_PREREQFUNC_OK;
}

static int fl_progress(
    void *userdata,
    curl_off_t download_total,
    curl_off_t download_now,
    curl_off_t upload_total,
    curl_off_t upload_now) {
  (void)download_total;
  (void)download_now;
  (void)upload_total;
  (void)upload_now;
  return fl_cancelled(userdata) ? 1 : 0;
}

static int fl_is_ows(uint8_t byte) {
  return byte == (uint8_t)' ' || byte == (uint8_t)'\t';
}

static int fl_is_retry_after_name(const uint8_t *bytes, size_t length) {
  static const uint8_t expected[] = "retry-after";
  if (bytes == NULL || length != sizeof(expected) - 1U) return 0;
  for (size_t index = 0U; index < length; index++) {
    uint8_t character = bytes[index];
    if (character >= (uint8_t)'A' && character <= (uint8_t)'Z')
      character = (uint8_t)(character + (uint8_t)('a' - 'A'));
    if (character != expected[index]) return 0;
  }
  return 1;
}

static int fl_parse_response_status(
    const uint8_t *line,
    size_t length,
    unsigned int *status_out) {
  if (line == NULL || status_out == NULL || length < 5U
      || memcmp(line, "HTTP/", 5U) != 0) return 0;
  for (size_t index = 0U; index < length; index++) {
    if (line[index] < 0x20U || line[index] > 0x7eU) return 0;
  }

  size_t cursor = 5U;
  size_t version_digits = 0U;
  while (cursor < length && line[cursor] >= (uint8_t)'0'
      && line[cursor] <= (uint8_t)'9') {
    cursor++;
    version_digits++;
  }
  if (version_digits == 0U) return 0;
  if (cursor < length && line[cursor] == (uint8_t)'.') {
    cursor++;
    size_t minor_digits = 0U;
    while (cursor < length && line[cursor] >= (uint8_t)'0'
        && line[cursor] <= (uint8_t)'9') {
      cursor++;
      minor_digits++;
    }
    if (minor_digits == 0U) return 0;
  }
  if (cursor >= length || line[cursor] != (uint8_t)' ') return 0;
  cursor++;
  if (length - cursor < 3U) return 0;
  if (line[cursor] < (uint8_t)'0' || line[cursor] > (uint8_t)'9'
      || line[cursor + 1U] < (uint8_t)'0' || line[cursor + 1U] > (uint8_t)'9'
      || line[cursor + 2U] < (uint8_t)'0' || line[cursor + 2U] > (uint8_t)'9')
    return 0;
  cursor += 3U;
  if (cursor < length && line[cursor] != (uint8_t)' ') return 0;

  unsigned int status = (unsigned int)(line[cursor - 3U] - (uint8_t)'0') * 100U
      + (unsigned int)(line[cursor - 2U] - (uint8_t)'0') * 10U
      + (unsigned int)(line[cursor - 1U] - (uint8_t)'0');
  if (status < 100U || status > 599U) return 0;
  *status_out = status;
  return 1;
}

static void fl_reset_response_header_block(struct fl_context *context) {
  context->response_retry_after_value_length = 0U;
  context->response_retry_after_field_count = 0U;
  context->response_retry_after_invalid = false;
  context->response_retry_after_last_field = false;
}

static void fl_begin_response_header_block(
    struct fl_context *context,
    unsigned int status) {
  context->response_retry_after_available = false;
  context->response_header_block_open = true;
  context->response_header_block_is_final = status >= 200U && status < 600U;
  fl_reset_response_header_block(context);
  if (!context->response_header_block_is_final) return;
  if (context->response_final_block_started)
    context->response_final_block_ambiguous = true;
  context->response_final_block_started = true;
}

static void fl_finish_response_header_block(struct fl_context *context) {
  if (!context->response_header_block_open) return;
  context->response_header_block_open = false;
  if (context->response_header_block_is_final
      && !context->response_final_block_ambiguous
      && context->response_retry_after_field_count == 1U
      && !context->response_retry_after_invalid
      && context->response_retry_after_value_length != 0U)
    context->response_retry_after_available = true;
}

static void fl_process_response_header_line(
    struct fl_context *context,
    const uint8_t *line,
    size_t length,
    int terminated) {
  if (context->response_body_started || line == NULL) return;
  if (terminated && length == 0U) {
    fl_finish_response_header_block(context);
    return;
  }

  if (length >= 5U && memcmp(line, "HTTP/", 5U) == 0) {
    if (context->response_header_block_open)
      context->response_final_block_ambiguous = true;
    context->response_retry_after_available = false;
    context->response_header_block_open = false;
    unsigned int status = 0U;
    if (!terminated || !fl_parse_response_status(line, length, &status)) {
      context->response_final_block_ambiguous = true;
      context->response_header_block_open = true;
      context->response_header_block_is_final = false;
      fl_reset_response_header_block(context);
      return;
    }
    fl_begin_response_header_block(context, status);
    return;
  }

  if (!context->response_header_block_open || length == 0U) return;
  if (fl_is_ows(line[0])) {
    if (context->response_retry_after_last_field)
      context->response_retry_after_invalid = true;
    context->response_retry_after_last_field = false;
    return;
  }

  context->response_retry_after_last_field = false;
  size_t colon = 0U;
  while (colon < length && line[colon] != (uint8_t)':') colon++;
  size_t name_length = colon;
  while (name_length > 0U && fl_is_ows(line[name_length - 1U])) name_length--;
  if (!fl_is_retry_after_name(line, name_length)) return;

  context->response_retry_after_last_field = true;
  if (context->response_retry_after_field_count != 0U) {
    context->response_retry_after_invalid = true;
    return;
  }
  context->response_retry_after_field_count = 1U;
  if (colon == length || name_length != colon || !terminated) {
    context->response_retry_after_invalid = true;
    return;
  }

  size_t value_start = colon + 1U;
  size_t value_end = length;
  while (value_start < value_end && fl_is_ows(line[value_start])) value_start++;
  while (value_end > value_start && fl_is_ows(line[value_end - 1U])) value_end--;
  size_t value_length = value_end - value_start;
  if (value_length == 0U || value_length > FL_MAX_RESPONSE_RETRY_AFTER_BYTES) {
    context->response_retry_after_invalid = true;
    return;
  }
  for (size_t index = value_start; index < value_end; index++) {
    if (line[index] < 0x20U || line[index] > 0x7eU) {
      context->response_retry_after_invalid = true;
      return;
    }
  }
  memcpy(context->response_retry_after_value, line + value_start, value_length);
  context->response_retry_after_value_length = value_length;
}

static size_t fl_copy_response_retry_after(
    const struct fl_context *context,
    uint8_t *value,
    size_t capacity) {
  if (context == NULL || value == NULL || context->response_header_failed
      || context->response_header_block_open || !context->response_retry_after_available
      || context->response_retry_after_value_length == 0U
      || context->response_retry_after_value_length > capacity) return 0U;
  memcpy(value, context->response_retry_after_value,
         context->response_retry_after_value_length);
  return context->response_retry_after_value_length;
}

static size_t fl_response_header(char *bytes, size_t size, size_t count, void *userdata) {
  struct fl_context *context = userdata;
  if (context == NULL) return 0U;
  if ((size != 0U && count > SIZE_MAX / size) || (bytes == NULL && size != 0U && count != 0U)) {
    context->response_header_failed = true;
    return 0U;
  }
  size_t length = size * count;
  if (context->response_header_bytes > FL_MAX_RESPONSE_HEADER_BYTES
      || length > FL_MAX_RESPONSE_HEADER_BYTES - context->response_header_bytes) {
    context->response_header_failed = true;
    return 0U;
  }
  context->response_header_bytes += length;
  size_t line_length = length;
  int terminated = length >= 2U
      && (uint8_t)bytes[length - 2U] == (uint8_t)'\r'
      && (uint8_t)bytes[length - 1U] == (uint8_t)'\n';
  if (terminated) line_length -= 2U;
  fl_process_response_header_line(
      context, (const uint8_t *)bytes, line_length, terminated);
  return length;
}

static size_t fl_response_body(char *bytes, size_t size, size_t count, void *userdata) {
  struct fl_context *context = userdata;
  if (context == NULL || (size != 0U && count > SIZE_MAX / size)) return 0U;
  context->response_body_started = true;
  size_t length = size * count;
  if (context->response_body_bytes > FL_MAX_RESPONSE_BODY_BYTES
      || length > FL_MAX_RESPONSE_BODY_BYTES - context->response_body_bytes
      || context->response_body_bytes > context->response_body_capacity
      || length > context->response_body_capacity - context->response_body_bytes)
    return 0U;
  if (length != 0U) {
    memcpy(context->response_body + context->response_body_bytes, bytes, length);
  }
  context->response_body_bytes += length;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (context->test != NULL && context->test->observation != NULL)
    context->test->observation->response_body_bytes = context->response_body_bytes;
#endif
  return length;
}

static struct curl_slist *fl_append_header(
    struct curl_slist *headers,
    const char *name,
    const char *value) {
  size_t name_length = strlen(name);
  size_t value_length = strlen(value);
  char *line = malloc(name_length + value_length + 3U);
  if (line == NULL) return NULL;
  memcpy(line, name, name_length);
  memcpy(line + name_length, ": ", 2U);
  memcpy(line + name_length + 2U, value, value_length + 1U);
  struct curl_slist *updated = curl_slist_append(headers, line);
  free(line);
  if (updated == NULL) return NULL;
  return updated;
}

static int fl_build_resolve_entry(
    const char *host,
    uint16_t port,
    int family,
    const char *address,
    char *entry,
    size_t capacity) {
  if (host == NULL || address == NULL || entry == NULL || capacity == 0U) return 0;
  char formatted_address[INET6_ADDRSTRLEN + 3U];
  if (family == AF_INET6) {
    int count = snprintf(formatted_address, sizeof(formatted_address), "[%s]", address);
    if (count < 0 || (size_t)count >= sizeof(formatted_address)) return 0;
  } else if (family == AF_INET) {
    size_t address_length = strnlen(address, sizeof(formatted_address));
    if (address_length == 0U || address_length >= sizeof(formatted_address)) return 0;
    memcpy(formatted_address, address, address_length + 1U);
  } else {
    return 0;
  }
  int count = snprintf(entry, capacity, "%s:%u:%s", host, (unsigned int)port,
                       formatted_address);
  return count > 0 && (size_t)count < capacity;
}

static uint64_t fl_monotonic_milliseconds(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0U;
  return (uint64_t)now.tv_sec * 1000U + (uint64_t)now.tv_nsec / 1000000U;
}

static int fl_perform(
    const struct fl_request *request
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
    , struct fl_test_configuration *test
#endif
    ) {
  if (request == NULL || request->response_body_length == NULL
      || request->status_code == NULL
      || request->response_retry_after_value_length == NULL)
    return FLECK_EVENT_HTTP_INVALID_REQUEST;
  *request->response_body_length = 0U;
  *request->status_code = 0;
  *request->response_retry_after_value_length = 0U;
  if (request->body_length > FL_MAX_REQUEST_BODY_BYTES
      || (request->body == NULL && request->body_length != 0U)
      || request->response_body == NULL
      || request->response_body_capacity < FL_MAX_RESPONSE_BODY_BYTES
      || (request->response_retry_after_value == NULL
          && request->response_retry_after_value_capacity != 0U)
      || !fl_validate_headers(request->headers, request->header_count))
    return FLECK_EVENT_HTTP_INVALID_REQUEST;
  if (!fl_curl_runtime_ready()) return FLECK_EVENT_HTTP_FAILURE;

  struct fl_url_parts parts;
  if (!fl_parse_url(request->url, &parts)) return FLECK_EVENT_HTTP_INVALID_REQUEST;
  int url_matches = fl_parts_match(&parts, request->host, request->port,
                                  request->request_target);
  fl_free_url_parts(&parts);
  if (!url_matches) return FLECK_EVENT_HTTP_INVALID_REQUEST;

  struct fl_context context;
  memset(&context, 0, sizeof(context));
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  context.test_socket = CURL_SOCKET_BAD;
#endif
  context.port = request->port;
  context.cancellation_check = request->cancellation_check;
  context.cancellation_context = request->cancellation_context;
  context.response_body = request->response_body;
  context.response_body_capacity = request->response_body_capacity;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  context.test = test;
#endif
  if (!fl_public_pin(request->pinned_address, request->port, &context.pin,
                     &context.pin_length, &context.pin_family))
    return FLECK_EVENT_HTTP_INVALID_REQUEST;

  uint32_t timeout_ms = request->timeout_ms;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (test != NULL && test->timeout_ms != 0U && test->timeout_ms < timeout_ms)
    timeout_ms = test->timeout_ms;
#endif
  if (timeout_ms == 0U || timeout_ms > FL_MAX_TIMEOUT_MS)
    return FLECK_EVENT_HTTP_INVALID_REQUEST;
  uint64_t now = fl_monotonic_milliseconds();
  if (now == 0U || now > UINT64_MAX - timeout_ms) return FLECK_EVENT_HTTP_FAILURE;
  context.deadline_ms = now + timeout_ms;

  const char *resolve_address = request->pinned_address;
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (test != NULL && test->resolve_address != NULL) resolve_address = test->resolve_address;
#endif
  char resolve_entry[FL_MAX_HOST_BYTES + INET6_ADDRSTRLEN + 32U];
  if (!fl_build_resolve_entry(request->host, request->port, context.pin_family,
                              resolve_address, resolve_entry, sizeof(resolve_entry)))
    return FLECK_EVENT_HTTP_INVALID_REQUEST;

  struct curl_slist *resolve = curl_slist_append(NULL, resolve_entry);
  struct curl_slist *curl_headers = NULL;
  if (resolve == NULL) return FLECK_EVENT_HTTP_FAILURE;
  for (size_t index = 0U; index < request->header_count; index++) {
    struct curl_slist *updated = fl_append_header(
        curl_headers, request->headers[index].name, request->headers[index].value);
    if (updated == NULL) {
      curl_slist_free_all(curl_headers);
      curl_slist_free_all(resolve);
      return FLECK_EVENT_HTTP_FAILURE;
    }
    curl_headers = updated;
  }
  struct curl_slist *updated = fl_append_header(curl_headers, "Connection", "close");
  if (updated == NULL) {
    curl_slist_free_all(curl_headers);
    curl_slist_free_all(resolve);
    return FLECK_EVENT_HTTP_FAILURE;
  }
  curl_headers = updated;
  updated = curl_slist_append(curl_headers, "Accept:");
  if (updated == NULL) {
    curl_slist_free_all(curl_headers);
    curl_slist_free_all(resolve);
    return FLECK_EVENT_HTTP_FAILURE;
  }
  curl_headers = updated;
  updated = curl_slist_append(curl_headers, "Expect:");
  if (updated == NULL) {
    curl_slist_free_all(curl_headers);
    curl_slist_free_all(resolve);
    return FLECK_EVENT_HTTP_FAILURE;
  }
  curl_headers = updated;

  CURL *handle = curl_easy_init();
  if (handle == NULL) {
    curl_slist_free_all(curl_headers);
    curl_slist_free_all(resolve);
    return FLECK_EVENT_HTTP_FAILURE;
  }
  CURLcode code = CURLE_OK;
  int result = FLECK_EVENT_HTTP_FAILURE;
  long status = 0L;
  uint32_t connect_timeout = timeout_ms < FL_MAX_CONNECT_TIMEOUT_MS
      ? timeout_ms : FL_MAX_CONNECT_TIMEOUT_MS;
  char error_buffer[CURL_ERROR_SIZE] = {0};
  static const char empty_body[] = "";

#define FL_SETOPT(option, value) \
  do { \
    code = curl_easy_setopt(handle, option, value); \
    if (code != CURLE_OK) goto cleanup; \
  } while (0)

  FL_SETOPT(CURLOPT_URL, request->url);
  FL_SETOPT(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
  FL_SETOPT(CURLOPT_PROTOCOLS_STR, "https");
  FL_SETOPT(CURLOPT_REDIR_PROTOCOLS_STR, "https");
  FL_SETOPT(CURLOPT_RESOLVE, resolve);
  FL_SETOPT(CURLOPT_DNS_CACHE_TIMEOUT, 0L);
  FL_SETOPT(CURLOPT_IPRESOLVE,
            context.pin_family == AF_INET ? CURL_IPRESOLVE_V4 : CURL_IPRESOLVE_V6);
  FL_SETOPT(CURLOPT_OPENSOCKETFUNCTION, fl_open_socket);
  FL_SETOPT(CURLOPT_OPENSOCKETDATA, &context);
  FL_SETOPT(CURLOPT_NOSIGNAL, 1L);
  FL_SETOPT(CURLOPT_SOCKOPTFUNCTION, fl_socket_options);
  FL_SETOPT(CURLOPT_SOCKOPTDATA, &context);
  FL_SETOPT(CURLOPT_PREREQFUNCTION, fl_prerequest);
  FL_SETOPT(CURLOPT_PREREQDATA, &context);
  FL_SETOPT(CURLOPT_XFERINFOFUNCTION, fl_progress);
  FL_SETOPT(CURLOPT_XFERINFODATA, &context);
  FL_SETOPT(CURLOPT_NOPROGRESS, 0L);
  FL_SETOPT(CURLOPT_HEADERFUNCTION, fl_response_header);
  FL_SETOPT(CURLOPT_HEADERDATA, &context);
  FL_SETOPT(CURLOPT_WRITEFUNCTION, fl_response_body);
  FL_SETOPT(CURLOPT_WRITEDATA, &context);
  FL_SETOPT(CURLOPT_FOLLOWLOCATION, 0L);
  FL_SETOPT(CURLOPT_MAXREDIRS, 0L);
  FL_SETOPT(CURLOPT_POSTREDIR, 0L);
  FL_SETOPT(CURLOPT_UNRESTRICTED_AUTH, 0L);
  FL_SETOPT(CURLOPT_PROXY, "");
  FL_SETOPT(CURLOPT_PRE_PROXY, "");
  FL_SETOPT(CURLOPT_NOPROXY, "*");
  FL_SETOPT(CURLOPT_SSL_VERIFYPEER, 1L);
  FL_SETOPT(CURLOPT_SSL_VERIFYHOST, 2L);
  FL_SETOPT(CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);
  FL_SETOPT(CURLOPT_FRESH_CONNECT, 1L);
  FL_SETOPT(CURLOPT_FORBID_REUSE, 1L);
  FL_SETOPT(CURLOPT_MAXCONNECTS, 1L);
  FL_SETOPT(CURLOPT_ALTSVC, (char *)NULL);
  FL_SETOPT(CURLOPT_HSTS_CTRL, 0L);
  FL_SETOPT(CURLOPT_NETRC, CURL_NETRC_IGNORED);
  FL_SETOPT(CURLOPT_HTTPAUTH, CURLAUTH_NONE);
  FL_SETOPT(CURLOPT_USERNAME, (char *)NULL);
  FL_SETOPT(CURLOPT_PASSWORD, (char *)NULL);
  FL_SETOPT(CURLOPT_USERPWD, (char *)NULL);
  FL_SETOPT(CURLOPT_PROXYUSERNAME, (char *)NULL);
  FL_SETOPT(CURLOPT_PROXYPASSWORD, (char *)NULL);
  FL_SETOPT(CURLOPT_PROXYUSERPWD, (char *)NULL);
  FL_SETOPT(CURLOPT_COOKIE, (char *)NULL);
  FL_SETOPT(CURLOPT_COOKIEFILE, (char *)NULL);
  FL_SETOPT(CURLOPT_COOKIEJAR, (char *)NULL);
  FL_SETOPT(CURLOPT_USERAGENT, (char *)NULL);
  FL_SETOPT(CURLOPT_ACCEPT_ENCODING, (char *)NULL);
  FL_SETOPT(CURLOPT_HTTP_CONTENT_DECODING, 0L);
  FL_SETOPT(CURLOPT_VERBOSE, 0L);
  FL_SETOPT(CURLOPT_FAILONERROR, 0L);
  FL_SETOPT(CURLOPT_MAXFILESIZE_LARGE, (curl_off_t)FL_MAX_RESPONSE_BODY_BYTES);
  FL_SETOPT(CURLOPT_TCP_KEEPALIVE, 0L);
  FL_SETOPT(CURLOPT_CONNECTTIMEOUT_MS, (long)connect_timeout);
  FL_SETOPT(CURLOPT_TIMEOUT_MS, (long)timeout_ms);
  FL_SETOPT(CURLOPT_ERRORBUFFER, error_buffer);
  FL_SETOPT(CURLOPT_HTTPHEADER, curl_headers);
  FL_SETOPT(CURLOPT_POST, 1L);
  FL_SETOPT(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)request->body_length);
  FL_SETOPT(CURLOPT_POSTFIELDS,
            request->body_length == 0U ? empty_body : (const char *)request->body);
  FL_SETOPT(CURLOPT_REQUEST_TARGET, request->request_target);
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (test != NULL && test->certificate_path != NULL)
    FL_SETOPT(CURLOPT_CAINFO, test->certificate_path);
#endif

  if (fl_cancelled(&context)) {
    result = context.cancelled ? FLECK_EVENT_HTTP_CANCELLED : FLECK_EVENT_HTTP_FAILURE;
    goto cleanup;
  }
  code = curl_easy_perform(handle);
  if (code == CURLE_OK) {
    if (curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &status) != CURLE_OK) goto cleanup;
    *request->response_body_length = context.response_body_bytes;
    *request->status_code = (int64_t)status;
    *request->response_retry_after_value_length = fl_copy_response_retry_after(
        &context, request->response_retry_after_value,
        request->response_retry_after_value_capacity);
    result = FLECK_EVENT_HTTP_SUCCESS;
  } else if (context.cancelled) {
    result = FLECK_EVENT_HTTP_CANCELLED;
  }

cleanup:
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  if (test != NULL && test->observation != NULL) {
    test->observation->curl_code = (int32_t)code;
    test->observation->status_code = (int64_t)status;
  }
#endif
  curl_easy_cleanup(handle);
  curl_slist_free_all(curl_headers);
  curl_slist_free_all(resolve);
  return result;

#undef FL_SETOPT
}

int fleck_event_http_validate_url(
    const char *url,
    const char *expected_host,
    uint16_t expected_port,
    const char *expected_request_target) {
  struct fl_url_parts parts;
  if (!fl_parse_url(url, &parts)) return 0;
  int matches = fl_parts_match(&parts, expected_host, expected_port,
                               expected_request_target);
  fl_free_url_parts(&parts);
  return matches;
}

int fleck_event_http_post(
    const char *url,
    const char *host,
    uint16_t port,
    const char *request_target,
    const char *pinned_address,
    const uint8_t *body,
    size_t body_length,
    const FleckEventHTTPHeader *headers,
    size_t header_count,
    uint32_t timeout_ms,
    FleckEventHTTPCancellationCheck cancellation_check,
    void *cancellation_context,
    uint8_t *response_body,
    size_t response_body_capacity,
    size_t *response_body_length,
    int64_t *status_code,
    uint8_t *response_retry_after_value,
    size_t response_retry_after_value_capacity,
    size_t *response_retry_after_value_length) {
  struct fl_request request = {
    .url = url,
    .host = host,
    .port = port,
    .request_target = request_target,
    .pinned_address = pinned_address,
    .body = body,
    .body_length = body_length,
    .headers = headers,
    .header_count = header_count,
    .timeout_ms = timeout_ms,
    .cancellation_check = cancellation_check,
    .cancellation_context = cancellation_context,
    .response_body = response_body,
    .response_body_capacity = response_body_capacity,
    .response_body_length = response_body_length,
    .status_code = status_code,
    .response_retry_after_value = response_retry_after_value,
    .response_retry_after_value_capacity = response_retry_after_value_capacity,
    .response_retry_after_value_length = response_retry_after_value_length,
  };
#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
  return fl_perform(&request, NULL);
#else
  return fl_perform(&request);
#endif
}

#ifdef FLECK_EVENT_HTTP_TEST_SUPPORT
struct FleckEventHTTPTestCancellation {
  atomic_bool cancelled;
};

static int fl_test_is_cancelled(void *context) {
  FleckEventHTTPTestCancellation *cancellation = context;
  return cancellation != NULL && atomic_load(&cancellation->cancelled);
}

FleckEventHTTPTestCancellation *FleckEventHTTPTestCancellationCreate(void) {
  return calloc(1, sizeof(FleckEventHTTPTestCancellation));
}

void FleckEventHTTPTestCancellationCancel(FleckEventHTTPTestCancellation *cancellation) {
  if (cancellation != NULL) atomic_store(&cancellation->cancelled, true);
}

void FleckEventHTTPTestCancellationDestroy(FleckEventHTTPTestCancellation *cancellation) {
  free(cancellation);
}

struct fl_saved_environment {
  const char *name;
  char *value;
  int was_present;
};

static pthread_mutex_t fl_test_environment_lock = PTHREAD_MUTEX_INITIALIZER;

static void fl_save_environment(struct fl_saved_environment *saved, const char *name) {
  saved->name = name;
  const char *value = getenv(name);
  saved->was_present = value != NULL;
  saved->value = value == NULL ? NULL : strdup(value);
}

static void fl_restore_environment(struct fl_saved_environment *saved, size_t count) {
  for (size_t index = 0U; index < count; index++) {
    if (saved[index].was_present) setenv(saved[index].name, saved[index].value, 1);
    else unsetenv(saved[index].name);
    free(saved[index].value);
  }
}

int32_t FleckEventHTTPTestPerform(
    const FleckEventHTTPTestRequest *test_request,
    FleckEventHTTPTestObservation *observation) {
  if (test_request == NULL || observation == NULL) return FLECK_EVENT_HTTP_INVALID_REQUEST;
  memset(observation, 0, sizeof(*observation));
  struct fl_url_parts parts;
  if (!fl_parse_url(test_request->url, &parts)) return FLECK_EVENT_HTTP_INVALID_REQUEST;

  FleckEventHTTPHeader headers[FL_MAX_REQUEST_HEADERS] = {
    {"content-type", "application/json"},
    {"webhook-id", test_request->webhook_id},
    {"webhook-timestamp", test_request->webhook_timestamp},
    {"webhook-signature", test_request->webhook_signature},
    {"x-mcp-subscription-id", test_request->subscription_id},
  };
  FleckEventHTTPTestCancellation *owned_cancellation = NULL;
  FleckEventHTTPTestCancellation *cancellation = test_request->cancellation;
  if (cancellation == NULL) {
    owned_cancellation = FleckEventHTTPTestCancellationCreate();
    cancellation = owned_cancellation;
  }
  if (cancellation == NULL) {
    fl_free_url_parts(&parts);
    return FLECK_EVENT_HTTP_FAILURE;
  }

  struct fl_test_configuration test = {
    .certificate_path = test_request->certificate_path,
    .resolve_address = test_request->resolve_address,
    .loopback_port = test_request->loopback_port,
    .timeout_ms = test_request->timeout_ms,
    .flags = test_request->flags,
    .cancellation_context = cancellation,
    .cancellation_check = fl_test_is_cancelled,
    .observation = observation,
  };
  uint8_t response_retry_after_value[FL_MAX_RESPONSE_RETRY_AFTER_BYTES];
  memset(response_retry_after_value, 0xa5, sizeof(response_retry_after_value));
  struct fl_request request = {
    .url = test_request->url,
    .host = parts.host,
    .port = parts.effective_port,
    .request_target = parts.request_target,
    .pinned_address = test_request->pin_address,
    .body = test_request->body,
    .body_length = test_request->body_length,
    .headers = headers,
    .header_count = FL_MAX_REQUEST_HEADERS,
    .timeout_ms = test_request->timeout_ms,
    .cancellation_check = fl_test_is_cancelled,
    .cancellation_context = cancellation,
    .response_body = malloc(FL_MAX_RESPONSE_BODY_BYTES),
    .response_body_capacity = FL_MAX_RESPONSE_BODY_BYTES,
    .response_body_length = NULL,
    .status_code = NULL,
    .response_retry_after_value = response_retry_after_value,
    .response_retry_after_value_capacity = sizeof(response_retry_after_value),
    .response_retry_after_value_length = NULL,
  };
  size_t response_body_length = 0U;
  size_t response_retry_after_value_length = SIZE_MAX;
  int64_t status_code = 0;
  request.response_body_length = &response_body_length;
  request.status_code = &status_code;
  request.response_retry_after_value_length = &response_retry_after_value_length;
  if (request.response_body == NULL) {
    free(owned_cancellation);
    fl_free_url_parts(&parts);
    return FLECK_EVENT_HTTP_FAILURE;
  }

  struct fl_saved_environment saved[11] = {0};
  const char *names[11] = {
    "http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY", "all_proxy",
    "ALL_PROXY", "ftp_proxy", "FTP_PROXY", "no_proxy", "NO_PROXY", "GIT_PROXY_COMMAND",
  };
  int use_hostile_proxy = (test_request->flags & 1U) != 0U;
  if (use_hostile_proxy) {
    pthread_mutex_lock(&fl_test_environment_lock);
    for (size_t index = 0U; index < 11U; index++) fl_save_environment(&saved[index], names[index]);
    const char *proxy = "http://192.0.2.1:9";
    setenv("http_proxy", proxy, 1);
    setenv("HTTP_PROXY", proxy, 1);
    setenv("https_proxy", proxy, 1);
    setenv("HTTPS_PROXY", proxy, 1);
    setenv("all_proxy", proxy, 1);
    setenv("ALL_PROXY", proxy, 1);
    setenv("ftp_proxy", proxy, 1);
    setenv("FTP_PROXY", proxy, 1);
    unsetenv("no_proxy");
    unsetenv("NO_PROXY");
  }

  int result = fl_perform(&request, &test);
  if (use_hostile_proxy) {
    fl_restore_environment(saved, 11U);
    pthread_mutex_unlock(&fl_test_environment_lock);
  }
  observation->response_body_bytes = (uint64_t)response_body_length;
  observation->status_code = status_code;
  observation->response_retry_after_bytes = (uint64_t)response_retry_after_value_length;
  free(request.response_body);
  free(owned_cancellation);
  fl_free_url_parts(&parts);
  return (int32_t)result;
}
#endif
