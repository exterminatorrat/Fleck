#ifndef FLECK_EVENT_HTTP_TEST_SUPPORT_H
#define FLECK_EVENT_HTTP_TEST_SUPPORT_H

#include <stddef.h>
#include <stdint.h>

typedef struct FleckEventHTTPTestCancellation FleckEventHTTPTestCancellation;
typedef struct FleckEventHTTPTestResponseCallbacks FleckEventHTTPTestResponseCallbacks;

enum {
  FLECK_EVENT_HTTP_TEST_HOSTILE_PROXY = 1U,
  FLECK_EVENT_HTTP_TEST_CANCEL_AT_PREREQUEST = 2U
};

typedef struct {
  const char *url;
  const char *pin_address;
  const char *resolve_address;
  const char *certificate_path;
  const uint8_t *body;
  size_t body_length;
  const char *webhook_id;
  const char *webhook_timestamp;
  const char *webhook_signature;
  const char *subscription_id;
  uint16_t loopback_port;
  uint32_t timeout_ms;
  uint32_t flags;
  FleckEventHTTPTestCancellation *cancellation;
} FleckEventHTTPTestRequest;

typedef struct {
  int32_t curl_code;
  uint32_t opensocket_calls;
  uint32_t pin_matches;
  uint32_t sockets_created;
  uint32_t pre_request_calls;
  uint32_t pin_rejected;
  int64_t status_code;
  uint64_t response_body_bytes;
  uint64_t response_retry_after_bytes;
} FleckEventHTTPTestObservation;

int FleckEventHTTPTestValidateSignature(const char *value);
FleckEventHTTPTestCancellation *FleckEventHTTPTestCancellationCreate(void);
void FleckEventHTTPTestCancellationCancel(FleckEventHTTPTestCancellation *cancellation);
void FleckEventHTTPTestCancellationDestroy(FleckEventHTTPTestCancellation *cancellation);
FleckEventHTTPTestResponseCallbacks *FleckEventHTTPTestResponseCallbacksCreate(void);
void FleckEventHTTPTestResponseCallbacksDestroy(
    FleckEventHTTPTestResponseCallbacks *callbacks);
size_t FleckEventHTTPTestResponseCallbacksHeader(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    const uint8_t *bytes,
    size_t length);
size_t FleckEventHTTPTestResponseCallbacksBody(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    const uint8_t *bytes,
    size_t length);
int FleckEventHTTPTestResponseCallbacksCopyRetryAfter(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    uint8_t *value,
    size_t capacity,
    size_t *value_length);
int32_t FleckEventHTTPTestPerform(
    const FleckEventHTTPTestRequest *request,
    FleckEventHTTPTestObservation *observation);
uint64_t FleckEventHTTPTestSIGPIPEFingerprint(void);

#endif
