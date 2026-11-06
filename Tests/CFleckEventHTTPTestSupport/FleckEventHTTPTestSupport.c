#include "FleckEventHTTPTestSupport.h"

#include <stdlib.h>

#ifdef FLECK_EVENT_HTTP_INIT_PROBE
#include <curl/curl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <time.h>

#undef curl_easy_setopt
#undef curl_easy_getinfo

enum {
  FL_PROBE_API_URL = 1U,
  FL_PROBE_API_TRANSFER = 2U,
};

static _Atomic unsigned int fl_probe_global_init_calls;
static _Atomic unsigned int fl_probe_version_info_calls;
static _Atomic unsigned int fl_probe_url_api_calls;
static _Atomic unsigned int fl_probe_transfer_api_calls;
static _Atomic unsigned int fl_probe_api_calls_before_init;
static _Atomic unsigned int fl_probe_api_calls_after_init_failure;
static _Atomic unsigned int fl_probe_threadsafe_feature;
static _Atomic unsigned int fl_probe_feature_mask;
static _Atomic int fl_probe_init_state;
static _Atomic int fl_probe_fail_global_init;
static _Atomic int fl_probe_delay_global_init;

static void fl_probe_note_curl_api(unsigned int kind);
static CURLcode fl_probe_curl_global_init(long flags);
const curl_version_info_data *fl_probe_curl_version_info(CURLversion age);

#define curl_global_init(flags) fl_probe_curl_global_init(flags)
#define curl_version_info(age) fl_probe_curl_version_info(age)
#define curl_url() (fl_probe_note_curl_api(FL_PROBE_API_URL), curl_url())
#define curl_url_set(...) (fl_probe_note_curl_api(FL_PROBE_API_URL), curl_url_set(__VA_ARGS__))
#define curl_url_get(...) (fl_probe_note_curl_api(FL_PROBE_API_URL), curl_url_get(__VA_ARGS__))
#define curl_url_cleanup(...) (fl_probe_note_curl_api(FL_PROBE_API_URL), curl_url_cleanup(__VA_ARGS__))
#define curl_free(...) (fl_probe_note_curl_api(FL_PROBE_API_URL), curl_free(__VA_ARGS__))
#define curl_slist_append(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_slist_append(__VA_ARGS__))
#define curl_slist_free_all(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_slist_free_all(__VA_ARGS__))
#define curl_easy_init() (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_easy_init())
#define curl_easy_setopt(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_easy_setopt(__VA_ARGS__))
#define curl_easy_perform(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_easy_perform(__VA_ARGS__))
#define curl_easy_getinfo(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_easy_getinfo(__VA_ARGS__))
#define curl_easy_cleanup(...) (fl_probe_note_curl_api(FL_PROBE_API_TRANSFER), curl_easy_cleanup(__VA_ARGS__))
#endif

#define FLECK_EVENT_HTTP_TEST_SUPPORT 1
#define fleck_event_http_is_public_address fleck_event_http_test_is_public_address
#define fleck_event_http_validate_url fleck_event_http_test_validate_url
#define fleck_event_http_post fleck_event_http_test_post

#include "../../Sources/CFleckEventHTTP/FleckEventHTTP.c"

int FleckEventHTTPTestValidateSignature(const char *value) {
  const FleckEventHTTPHeader headers[] = {
    {"content-type", "application/json"},
    {"webhook-id", "evt_overlap"},
    {"webhook-timestamp", "1729000000"},
    {"webhook-signature", value},
    {"x-mcp-subscription-id", "evt_"
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  };
  return fl_validate_headers(headers, sizeof(headers) / sizeof(headers[0]));
}

struct FleckEventHTTPTestResponseCallbacks {
  struct fl_context context;
  uint8_t response_body[FL_MAX_RESPONSE_BODY_BYTES];
};

FleckEventHTTPTestResponseCallbacks *FleckEventHTTPTestResponseCallbacksCreate(void) {
  FleckEventHTTPTestResponseCallbacks *callbacks = calloc(1, sizeof(*callbacks));
  if (callbacks == NULL) return NULL;
  callbacks->context.response_body = callbacks->response_body;
  callbacks->context.response_body_capacity = sizeof(callbacks->response_body);
  return callbacks;
}

void FleckEventHTTPTestResponseCallbacksDestroy(
    FleckEventHTTPTestResponseCallbacks *callbacks) {
  free(callbacks);
}

size_t FleckEventHTTPTestResponseCallbacksHeader(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    const uint8_t *bytes,
    size_t length) {
  if (callbacks == NULL || (bytes == NULL && length != 0U)) return 0U;
  return fl_response_header((char *)bytes, 1U, length, &callbacks->context);
}

size_t FleckEventHTTPTestResponseCallbacksBody(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    const uint8_t *bytes,
    size_t length) {
  if (callbacks == NULL || (bytes == NULL && length != 0U)) return 0U;
  return fl_response_body((char *)bytes, 1U, length, &callbacks->context);
}

int FleckEventHTTPTestResponseCallbacksCopyRetryAfter(
    FleckEventHTTPTestResponseCallbacks *callbacks,
    uint8_t *value,
    size_t capacity,
    size_t *value_length) {
  if (callbacks == NULL || value_length == NULL || (value == NULL && capacity != 0U)) return 0;
  *value_length = fl_copy_response_retry_after(&callbacks->context, value, capacity);
  return 1;
}

#ifdef FLECK_EVENT_HTTP_INIT_PROBE
#undef curl_global_init
#undef curl_version_info
#undef curl_url
#undef curl_url_set
#undef curl_url_get
#undef curl_url_cleanup
#undef curl_free
#undef curl_slist_append
#undef curl_slist_free_all
#undef curl_easy_init
#undef curl_easy_setopt
#undef curl_easy_perform
#undef curl_easy_getinfo
#undef curl_easy_cleanup

static void fl_probe_note_curl_api(unsigned int kind) {
  atomic_fetch_add_explicit(&fl_probe_url_api_calls,
                            kind == FL_PROBE_API_URL ? 1U : 0U,
                            memory_order_relaxed);
  atomic_fetch_add_explicit(&fl_probe_transfer_api_calls,
                            kind == FL_PROBE_API_TRANSFER ? 1U : 0U,
                            memory_order_relaxed);
  int state = atomic_load_explicit(&fl_probe_init_state, memory_order_acquire);
  if (state == 0) {
    atomic_fetch_add_explicit(&fl_probe_api_calls_before_init, 1U, memory_order_relaxed);
  } else if (state < 0) {
    atomic_fetch_add_explicit(&fl_probe_api_calls_after_init_failure, 1U, memory_order_relaxed);
  }
}

static CURLcode fl_probe_curl_global_init(long flags) {
  atomic_fetch_add_explicit(&fl_probe_global_init_calls, 1U, memory_order_relaxed);
  if (atomic_load_explicit(&fl_probe_fail_global_init, memory_order_relaxed) != 0) {
    atomic_store_explicit(&fl_probe_init_state, -1, memory_order_release);
    return CURLE_FAILED_INIT;
  }
  if (atomic_load_explicit(&fl_probe_delay_global_init, memory_order_relaxed) != 0) {
    const struct timespec delay = {.tv_sec = 0, .tv_nsec = 20000000};
    nanosleep(&delay, NULL);
  }
  CURLcode result = curl_global_init(flags);
  atomic_store_explicit(&fl_probe_init_state, result == CURLE_OK ? 1 : -1, memory_order_release);
  return result;
}

const curl_version_info_data *fl_probe_curl_version_info(CURLversion age) {
  atomic_fetch_add_explicit(&fl_probe_version_info_calls, 1U, memory_order_relaxed);
  int state = atomic_load_explicit(&fl_probe_init_state, memory_order_acquire);
  if (state == 0) {
    atomic_fetch_add_explicit(&fl_probe_api_calls_before_init, 1U, memory_order_relaxed);
  } else if (state < 0) {
    atomic_fetch_add_explicit(&fl_probe_api_calls_after_init_failure, 1U, memory_order_relaxed);
  }
  const curl_version_info_data *version = curl_version_info(age);
  if (version != NULL) {
    unsigned int features = (unsigned int)version->features;
    atomic_store_explicit(&fl_probe_feature_mask, features, memory_order_relaxed);
    atomic_store_explicit(&fl_probe_threadsafe_feature,
                          (features & (unsigned int)CURL_VERSION_THREADSAFE) != 0U,
                          memory_order_relaxed);
  }
  return version;
}

static void fl_probe_print_state(const char *scenario, int result, uint32_t socket_calls) {
  printf("scenario=%s\n", scenario);
  printf("result=%d\n", result);
  printf("global_init_calls=%u\n", atomic_load(&fl_probe_global_init_calls));
  printf("version_info_calls=%u\n", atomic_load(&fl_probe_version_info_calls));
  printf("url_api_calls=%u\n", atomic_load(&fl_probe_url_api_calls));
  printf("transfer_api_calls=%u\n", atomic_load(&fl_probe_transfer_api_calls));
  printf("api_calls_before_init=%u\n", atomic_load(&fl_probe_api_calls_before_init));
  printf("api_calls_after_init_failure=%u\n",
         atomic_load(&fl_probe_api_calls_after_init_failure));
  printf("socket_calls=%u\n", socket_calls);
  printf("threadsafe_feature=%u\n", atomic_load(&fl_probe_threadsafe_feature));
  printf("feature_mask=0x%08x\n", atomic_load(&fl_probe_feature_mask));
}

static int fl_probe_init_failure(const char *scenario, int perform_transfer) {
  atomic_store_explicit(&fl_probe_fail_global_init, 1, memory_order_relaxed);
  int result = 0;
  uint32_t socket_calls = 0U;
  if (perform_transfer != 0) {
    static const uint8_t body[] = "{}";
    FleckEventHTTPTestRequest request = {
      .url = "https://hook.example/hook",
      .pin_address = "93.184.216.34",
      .body = body,
      .body_length = sizeof(body) - 1U,
      .webhook_id = "evt_init_failure",
      .webhook_timestamp = "1729000000",
      .webhook_signature = "v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
      .subscription_id = "evt_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      .loopback_port = 443U,
      .timeout_ms = 1000U,
    };
    FleckEventHTTPTestObservation observation = {0};
    result = (int)FleckEventHTTPTestPerform(&request, &observation);
    socket_calls = observation.opensocket_calls;
  } else {
    result = fleck_event_http_test_validate_url(
        "https://hook.example/hook", "hook.example", 443U, "/hook");
  }
  fl_probe_print_state(scenario, result, socket_calls);
  int unexpected_result = perform_transfer != 0
      ? result == FLECK_EVENT_HTTP_SUCCESS
      : result != 0;
  return unexpected_result
          || atomic_load(&fl_probe_global_init_calls) != 1U
          || atomic_load(&fl_probe_version_info_calls) != 0U
          || atomic_load(&fl_probe_url_api_calls) != 0U
          || atomic_load(&fl_probe_transfer_api_calls) != 0U
          || atomic_load(&fl_probe_api_calls_before_init) != 0U
          || atomic_load(&fl_probe_api_calls_after_init_failure) != 0U
          || socket_calls != 0U
      ? 1 : 0;
}

struct fl_probe_start_gate {
  pthread_mutex_t mutex;
  pthread_cond_t condition;
  unsigned int ready;
  int go;
};

struct fl_probe_thread_argument {
  struct fl_probe_start_gate *gate;
  int result;
};

static void *fl_probe_validate_url(void *opaque) {
  struct fl_probe_thread_argument *argument = opaque;
  pthread_mutex_lock(&argument->gate->mutex);
  argument->gate->ready++;
  pthread_cond_broadcast(&argument->gate->condition);
  while (argument->gate->go == 0)
    pthread_cond_wait(&argument->gate->condition, &argument->gate->mutex);
  pthread_mutex_unlock(&argument->gate->mutex);
  argument->result = fleck_event_http_test_validate_url(
      "https://hook.example/a%2Fb?tenant=a%2Fb",
      "hook.example", 443U, "/a%2Fb?tenant=a%2Fb");
  return NULL;
}

static int fl_probe_concurrent_first_use(void) {
  enum { FL_PROBE_THREAD_COUNT = 8 };
  pthread_t threads[FL_PROBE_THREAD_COUNT];
  struct fl_probe_thread_argument arguments[FL_PROBE_THREAD_COUNT];
  struct fl_probe_start_gate gate = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .condition = PTHREAD_COND_INITIALIZER,
    .ready = 0U,
    .go = 0,
  };
  unsigned int created = 0U;
  int create_failed = 0;
  atomic_store_explicit(&fl_probe_delay_global_init, 1, memory_order_relaxed);
  for (unsigned int index = 0U; index < FL_PROBE_THREAD_COUNT; index++) {
    arguments[index].gate = &gate;
    arguments[index].result = 0;
    if (pthread_create(&threads[index], NULL, fl_probe_validate_url, &arguments[index]) != 0) {
      create_failed = 1;
      break;
    }
    created++;
  }
  pthread_mutex_lock(&gate.mutex);
  while (gate.ready < created) pthread_cond_wait(&gate.condition, &gate.mutex);
  gate.go = 1;
  pthread_cond_broadcast(&gate.condition);
  pthread_mutex_unlock(&gate.mutex);

  unsigned int valid = 0U;
  for (unsigned int index = 0U; index < created; index++) {
    if (pthread_join(threads[index], NULL) != 0) create_failed = 1;
    if (arguments[index].result != 0) valid++;
  }
  fl_probe_print_state("concurrent-first-use", (int)valid, 0U);
  return create_failed != 0
          || created != FL_PROBE_THREAD_COUNT
          || valid != FL_PROBE_THREAD_COUNT
          || atomic_load(&fl_probe_global_init_calls) != 1U
          || atomic_load(&fl_probe_version_info_calls) != 1U
          || atomic_load(&fl_probe_url_api_calls) == 0U
          || atomic_load(&fl_probe_transfer_api_calls) != 0U
          || atomic_load(&fl_probe_api_calls_before_init) != 0U
          || atomic_load(&fl_probe_api_calls_after_init_failure) != 0U
          || atomic_load(&fl_probe_threadsafe_feature) == 0U
      ? 1 : 0;
}

int main(int argc, char **argv);
int main(int argc, char **argv) {
  if (argc != 2) return 64;
  if (strcmp(argv[1], "--validate-init-failure") == 0)
    return fl_probe_init_failure("validate-init-failure", 0);
  if (strcmp(argv[1], "--post-init-failure") == 0)
    return fl_probe_init_failure("post-init-failure", 1);
  if (strcmp(argv[1], "--concurrent-first-use") == 0)
    return fl_probe_concurrent_first_use();
  return 64;
}
#endif

#include <signal.h>

uint64_t FleckEventHTTPTestSIGPIPEFingerprint(void) {
  struct sigaction disposition;
  memset(&disposition, 0, sizeof(disposition));
  if (sigaction(SIGPIPE, NULL, &disposition) != 0) return 0U;

  uint64_t fingerprint = UINT64_C(1469598103934665603);
  const unsigned char *parts[] = {
      (const unsigned char *)&disposition.sa_handler,
      (const unsigned char *)&disposition.sa_flags,
      (const unsigned char *)&disposition.sa_mask,
  };
  const size_t lengths[] = {
      sizeof(disposition.sa_handler),
      sizeof(disposition.sa_flags),
      sizeof(disposition.sa_mask),
  };
  for (size_t part = 0U; part < sizeof(parts) / sizeof(parts[0]); part++) {
    for (size_t byte = 0U; byte < lengths[part]; byte++) {
      fingerprint ^= parts[part][byte];
      fingerprint *= UINT64_C(1099511628211);
    }
  }
  return fingerprint == 0U ? 1U : fingerprint;
}
