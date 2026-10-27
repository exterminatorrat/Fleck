#ifndef FLECK_EVENT_HTTP_H
#define FLECK_EVENT_HTTP_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  const char *name;
  const char *value;
} FleckEventHTTPHeader;

typedef int (*FleckEventHTTPCancellationCheck)(void *context);

enum {
  FLECK_EVENT_HTTP_MAX_RETRY_AFTER_VALUE_BYTES = 1024
};

enum {
  FLECK_EVENT_HTTP_SUCCESS = 0,
  FLECK_EVENT_HTTP_INVALID_REQUEST = 1,
  FLECK_EVENT_HTTP_CANCELLED = 2,
  FLECK_EVENT_HTTP_FAILURE = 3
};

int fleck_event_http_is_public_address(int family, const uint8_t *address, size_t length);

int fleck_event_http_validate_url(
    const char *url,
    const char *expected_host,
    uint16_t expected_port,
    const char *expected_request_target);

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
    size_t *response_retry_after_value_length);

#endif
