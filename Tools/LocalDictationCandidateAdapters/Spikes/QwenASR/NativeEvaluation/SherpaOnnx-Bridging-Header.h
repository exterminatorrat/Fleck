#import <SherpaOnnxC/sherpa-onnx/c-api/c-api.h>

#include <dlfcn.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef const SherpaOnnxOfflineRecognizer *(*FleckSherpaCreateRecognizerFunction)(
    const SherpaOnnxOfflineRecognizerConfig *config);
typedef void (*FleckSherpaDestroyRecognizerFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef const SherpaOnnxOfflineStream *(*FleckSherpaCreateStreamFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef void (*FleckSherpaDestroyStreamFunction)(
    const SherpaOnnxOfflineStream *stream);
typedef void (*FleckSherpaAcceptWaveformFunction)(
    const SherpaOnnxOfflineStream *stream, int32_t sample_rate,
    const float *samples, int32_t n);
typedef void (*FleckSherpaDecodeStreamFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer,
    const SherpaOnnxOfflineStream *stream);
typedef const SherpaOnnxOfflineRecognizerResult *(*FleckSherpaGetResultFunction)(
    const SherpaOnnxOfflineStream *stream);
typedef void (*FleckSherpaDestroyResultFunction)(
    const SherpaOnnxOfflineRecognizerResult *result);

typedef struct FleckSherpaSymbolTable {
  void *handle;
  FleckSherpaCreateRecognizerFunction create_recognizer;
  FleckSherpaDestroyRecognizerFunction destroy_recognizer;
  FleckSherpaCreateStreamFunction create_stream;
  FleckSherpaDestroyStreamFunction destroy_stream;
  FleckSherpaAcceptWaveformFunction accept_waveform;
  FleckSherpaDecodeStreamFunction decode_stream;
  FleckSherpaGetResultFunction get_result;
  FleckSherpaDestroyResultFunction destroy_result;
} FleckSherpaSymbolTable;

static inline int FleckSherpaStoreSymbol(
    void *symbol, void *destination, size_t destination_size) {
  _Static_assert(sizeof(void *) == sizeof(FleckSherpaCreateRecognizerFunction),
                 "arm64 function pointers must match dlsym pointers");
  if (symbol == NULL || destination_size != sizeof(symbol)) {
    return 0;
  }
  memcpy(destination, &symbol, destination_size);
  return 1;
}

static inline int FleckSherpaResolveSymbol(
    void *handle, const char *path, const char *name,
    void *destination, size_t destination_size) {
  void *symbol = dlsym(handle, name);
  if (symbol == NULL || !FleckSherpaStoreSymbol(symbol, destination, destination_size)) {
    return 0;
  }

  Dl_info info = {0};
  char expected_path[PATH_MAX];
  char loaded_path[PATH_MAX];
  if (dladdr(symbol, &info) == 0 || info.dli_fname == NULL ||
      realpath(path, expected_path) == NULL ||
      realpath(info.dli_fname, loaded_path) == NULL ||
      strcmp(expected_path, loaded_path) != 0) {
    return 0;
  }
  return 1;
}

static inline void *FleckSherpaOpenVerified(const char *path) {
  if (path == NULL) {
    return NULL;
  }

  if (getenv("FLECK_QWEN_NATIVE_OPEN_PROBE") != NULL) {
    static const char marker[] = "native-dlopen-attempted\n";
    (void)write(STDERR_FILENO, marker, sizeof(marker) - 1);
  }

  void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (handle == NULL) {
    return NULL;
  }

  FleckSherpaSymbolTable *table =
      (FleckSherpaSymbolTable *)calloc(1, sizeof(FleckSherpaSymbolTable));
  if (table == NULL) {
    dlclose(handle);
    return NULL;
  }
  table->handle = handle;

  int resolved =
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxCreateOfflineRecognizer",
                               &table->create_recognizer,
                               sizeof(table->create_recognizer)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxDestroyOfflineRecognizer",
                               &table->destroy_recognizer,
                               sizeof(table->destroy_recognizer)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxCreateOfflineStream",
                               &table->create_stream, sizeof(table->create_stream)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxDestroyOfflineStream",
                               &table->destroy_stream, sizeof(table->destroy_stream)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxAcceptWaveformOffline",
                               &table->accept_waveform,
                               sizeof(table->accept_waveform)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxDecodeOfflineStream",
                               &table->decode_stream,
                               sizeof(table->decode_stream)) &&
      FleckSherpaResolveSymbol(handle, path, "SherpaOnnxGetOfflineStreamResult",
                               &table->get_result, sizeof(table->get_result)) &&
      FleckSherpaResolveSymbol(handle, path,
                               "SherpaOnnxDestroyOfflineRecognizerResult",
                               &table->destroy_result,
                               sizeof(table->destroy_result));
  if (!resolved) {
    dlclose(handle);
    free(table);
    return NULL;
  }
  return table;
}

static inline void FleckSherpaCloseVerified(void *opaque_table) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table == NULL) {
    return;
  }
  void *handle = table->handle;
  table->handle = NULL;
  free(table);
  if (handle != NULL) {
    dlclose(handle);
  }
}

static inline const SherpaOnnxOfflineRecognizer *FleckSherpaCreateOfflineRecognizer(
    void *opaque_table, const SherpaOnnxOfflineRecognizerConfig *config) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  return table == NULL || table->create_recognizer == NULL
             ? NULL
             : table->create_recognizer(config);
}

static inline void FleckSherpaDestroyOfflineRecognizer(
    void *opaque_table, const SherpaOnnxOfflineRecognizer *recognizer) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table != NULL && table->destroy_recognizer != NULL && recognizer != NULL) {
    table->destroy_recognizer(recognizer);
  }
}

static inline const SherpaOnnxOfflineStream *FleckSherpaCreateOfflineStream(
    void *opaque_table, const SherpaOnnxOfflineRecognizer *recognizer) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  return table == NULL || table->create_stream == NULL
             ? NULL
             : table->create_stream(recognizer);
}

static inline void FleckSherpaDestroyOfflineStream(
    void *opaque_table, const SherpaOnnxOfflineStream *stream) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table != NULL && table->destroy_stream != NULL && stream != NULL) {
    table->destroy_stream(stream);
  }
}

static inline void FleckSherpaAcceptWaveformOffline(
    void *opaque_table, const SherpaOnnxOfflineStream *stream,
    int32_t sample_rate, const float *samples, int32_t n) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table != NULL && table->accept_waveform != NULL) {
    table->accept_waveform(stream, sample_rate, samples, n);
  }
}

static inline void FleckSherpaDecodeOfflineStream(
    void *opaque_table, const SherpaOnnxOfflineRecognizer *recognizer,
    const SherpaOnnxOfflineStream *stream) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table != NULL && table->decode_stream != NULL) {
    table->decode_stream(recognizer, stream);
  }
}

static inline const SherpaOnnxOfflineRecognizerResult *FleckSherpaGetOfflineStreamResult(
    void *opaque_table, const SherpaOnnxOfflineStream *stream) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  return table == NULL || table->get_result == NULL ? NULL : table->get_result(stream);
}

static inline const char *FleckSherpaOfflineResultText(
    void *opaque_table, const SherpaOnnxOfflineRecognizerResult *result) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  return table == NULL || result == NULL || table->handle == NULL ? NULL : result->text;
}

static inline void FleckSherpaDestroyOfflineRecognizerResult(
    void *opaque_table, const SherpaOnnxOfflineRecognizerResult *result) {
  FleckSherpaSymbolTable *table = (FleckSherpaSymbolTable *)opaque_table;
  if (table != NULL && table->destroy_result != NULL && result != NULL) {
    table->destroy_result(result);
  }
}
