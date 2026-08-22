#ifndef FLECK_NEMO_SPEECH_ASR_BRIDGING_HEADER_H
#define FLECK_NEMO_SPEECH_ASR_BRIDGING_HEADER_H

#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "nemo_speech/asr.h"

typedef nemo_speech_asr_status (*FleckNemoCreateFunction)(
    const nemo_speech_asr_recognizer_config*, nemo_speech_asr_recognizer**);
typedef void (*FleckNemoDestroyFunction)(nemo_speech_asr_recognizer*);
typedef nemo_speech_asr_status (*FleckNemoStreamOpenFunction)(
    nemo_speech_asr_recognizer*, const nemo_speech_asr_recognition_options*, nemo_speech_asr_stream**);
typedef nemo_speech_asr_status (*FleckNemoStreamPushFunction)(
    nemo_speech_asr_stream*, const float*, size_t, int32_t);
typedef nemo_speech_asr_status (*FleckNemoStreamFinishFunction)(nemo_speech_asr_stream*);
typedef nemo_speech_asr_status (*FleckNemoStreamNextFunction)(
    nemo_speech_asr_stream*, nemo_speech_asr_result**);
typedef void (*FleckNemoStreamCloseFunction)(nemo_speech_asr_stream*);
typedef bool (*FleckNemoResultIsFinalFunction)(const nemo_speech_asr_result*);
typedef const char* (*FleckNemoResultTranscriptFunction)(const nemo_speech_asr_result*, size_t);
typedef void (*FleckNemoResultDestroyFunction)(nemo_speech_asr_result*);
typedef const char* (*FleckNemoVersionFunction)(void);
typedef const char* (*FleckNemoLastErrorFunction)(void);

typedef struct FleckNemoFileIdentity {
    uint64_t device;
    uint64_t inode;
} FleckNemoFileIdentity;

typedef struct FleckNemoSymbolTable {
    void* handle;
    FleckNemoCreateFunction create;
    FleckNemoDestroyFunction destroy;
    FleckNemoStreamOpenFunction stream_open;
    FleckNemoStreamPushFunction stream_push;
    FleckNemoStreamFinishFunction stream_finish;
    FleckNemoStreamNextFunction stream_next;
    FleckNemoStreamCloseFunction stream_close;
    FleckNemoResultIsFinalFunction result_is_final;
    FleckNemoResultTranscriptFunction result_transcript;
    FleckNemoResultDestroyFunction result_destroy;
    FleckNemoVersionFunction version;
    FleckNemoLastErrorFunction last_error;
    void** dependency_handles;
    size_t dependency_count;
    char** expected_paths;
    FleckNemoFileIdentity* expected_identities;
    size_t expected_count;
    char expected_root[PATH_MAX];
    uint32_t baseline_image_count;
} FleckNemoSymbolTable;

static const char* const FleckNemoRuntimeLibraryNames[] = {
    "libggml-base.0.12.0.dylib",
    "libggml-blas.0.12.0.dylib",
    "libggml-cpu.0.12.0.dylib",
    "libggml-metal.0.12.0.dylib",
    "libggml.0.12.0.dylib",
    "libnemo_speech_asr.dylib",
    "libnemo_speech_asr_c.1.dylib",
};

static inline size_t FleckNemoRuntimeLibraryCount(void) {
    return sizeof(FleckNemoRuntimeLibraryNames) /
           sizeof(FleckNemoRuntimeLibraryNames[0]);
}

static inline int FleckNemoStoreSymbol(
    void* symbol, void* destination, size_t destination_size) {
    _Static_assert(sizeof(void*) == sizeof(FleckNemoCreateFunction),
                   "arm64 function pointers must match dlsym pointers");
    if (symbol == NULL || destination == NULL ||
        destination_size != sizeof(symbol)) {
        return 0;
    }
    memcpy(destination, &symbol, destination_size);
    return 1;
}

static inline int FleckNemoResolveSymbol(
    void* handle, const char* path, const char* name,
    void* destination, size_t destination_size) {
    void* symbol = dlsym(handle, name);
    if (!FleckNemoStoreSymbol(symbol, destination, destination_size)) {
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

static inline void FleckNemoWriteOpenProbe(void) {
    if (getenv("FLECK_NEMOTRON_NATIVE_OPEN_PROBE") != NULL) {
        static const char marker[] = "native-dlopen-attempted\n";
        (void)write(STDERR_FILENO, marker, sizeof(marker) - 1);
    }
}

static inline int FleckNemoCanonicalPath(
    const char* path, char output[PATH_MAX]) {
    return path != NULL && realpath(path, output) != NULL;
}

static inline int FleckNemoJoinPath(
    const char* root, const char* name, char output[PATH_MAX]) {
    if (root == NULL || name == NULL) {
        return 0;
    }
    int written = snprintf(output, PATH_MAX, "%s/%s", root, name);
    return written > 0 && written < PATH_MAX;
}

static inline int FleckNemoIsWithinRoot(
    const char* root, const char* path) {
    size_t root_length = strlen(root);
    return strncmp(root, path, root_length) == 0 &&
           path[root_length] == '/';
}

static inline int FleckNemoIsSystemImage(const char* path) {
    static const char* const system_roots[] = {
        "/System/Library/",
        "/System/Volumes/Preboot/Cryptexes/OS/System/Library/",
        "/System/Volumes/Preboot/Cryptexes/OS/usr/lib/",
        "/usr/lib/",
    };
    for (size_t index = 0;
         index < sizeof(system_roots) / sizeof(system_roots[0]); index++) {
        if (strncmp(path, system_roots[index], strlen(system_roots[index])) == 0) {
            return 1;
        }
    }
    return 0;
}

static inline int FleckNemoStatIdentity(
    const char* path, FleckNemoFileIdentity* identity) {
    struct stat value;
    if (path == NULL || identity == NULL || stat(path, &value) != 0 ||
        (value.st_mode & S_IFMT) != S_IFREG) {
        return 0;
    }
    identity->device = (uint64_t)value.st_dev;
    identity->inode = (uint64_t)value.st_ino;
    return 1;
}

static inline int FleckNemoSameIdentity(
    const char* path, const FleckNemoFileIdentity* expected) {
    FleckNemoFileIdentity observed;
    return FleckNemoStatIdentity(path, &observed) &&
           observed.device == expected->device &&
           observed.inode == expected->inode;
}

static inline void FleckNemoClearExpectedPaths(FleckNemoSymbolTable* table) {
    if (table == NULL) {
        return;
    }
    if (table->expected_paths != NULL) {
        for (size_t index = 0; index < table->expected_count; index++) {
            free(table->expected_paths[index]);
        }
    }
    free(table->expected_paths);
    free(table->expected_identities);
    table->expected_paths = NULL;
    table->expected_identities = NULL;
    table->expected_count = 0;
    table->expected_root[0] = '\0';
}

static inline int FleckNemoSetExpectedRoot(
    FleckNemoSymbolTable* table, const char* snapshot_root) {
    if (table == NULL || snapshot_root == NULL) {
        return 0;
    }
    char canonical_root[PATH_MAX];
    if (!FleckNemoCanonicalPath(snapshot_root, canonical_root)) {
        return 0;
    }
    if (table->expected_count != 0) {
        return strcmp(table->expected_root, canonical_root) == 0;
    }

    const size_t count = FleckNemoRuntimeLibraryCount();
    char** paths = (char**)calloc(count, sizeof(char*));
    FleckNemoFileIdentity* identities =
        (FleckNemoFileIdentity*)calloc(count, sizeof(FleckNemoFileIdentity));
    if (paths == NULL || identities == NULL) {
        free(paths);
        free(identities);
        return 0;
    }

    for (size_t index = 0; index < count; index++) {
        char joined[PATH_MAX];
        char canonical_path[PATH_MAX];
        if (!FleckNemoJoinPath(
                canonical_root, FleckNemoRuntimeLibraryNames[index], joined) ||
            !FleckNemoCanonicalPath(joined, canonical_path) ||
            !FleckNemoIsWithinRoot(canonical_root, canonical_path) ||
            !FleckNemoStatIdentity(canonical_path, &identities[index])) {
            for (size_t cleanup = 0; cleanup < index; cleanup++) {
                free(paths[cleanup]);
            }
            free(paths);
            free(identities);
            return 0;
        }
        paths[index] = strdup(canonical_path);
        if (paths[index] == NULL) {
            for (size_t cleanup = 0; cleanup <= index; cleanup++) {
                free(paths[cleanup]);
            }
            free(paths);
            free(identities);
            return 0;
        }
    }

    memcpy(table->expected_root, canonical_root, strlen(canonical_root) + 1);
    table->expected_paths = paths;
    table->expected_identities = identities;
    table->expected_count = count;
    return 1;
}

static inline int FleckNemoExpectedIndex(
    const FleckNemoSymbolTable* table, const char* path) {
    if (table == NULL || path == NULL) {
        return -1;
    }
    for (size_t index = 0; index < table->expected_count; index++) {
        if (strcmp(table->expected_paths[index], path) == 0) {
            return (int)index;
        }
    }
    return -1;
}

static inline int FleckNemoExpectedBasenameIndex(const char* path) {
    const char* basename = strrchr(path, '/');
    basename = basename == NULL ? path : basename + 1;
    for (size_t index = 0; index < FleckNemoRuntimeLibraryCount(); index++) {
        if (strcmp(FleckNemoRuntimeLibraryNames[index], basename) == 0) {
            return (int)index;
        }
    }
    return -1;
}

static inline int FleckNemoVerifyRuntimeProvenance(
    void* opaque_table, const char* snapshot_root) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL) {
        return 0;
    }
    if (!FleckNemoSetExpectedRoot(table, snapshot_root)) {
        return 0;
    }

    const size_t count = table->expected_count;
    unsigned char* seen = (unsigned char*)calloc(count, sizeof(unsigned char));
    if (seen == NULL) {
        return 0;
    }
    int valid = 1;
    const uint32_t image_count = _dyld_image_count();
    for (uint32_t index = 0; index < image_count; index++) {
        const char* image_name = _dyld_get_image_name(index);
        if (image_name == NULL) {
            valid = index < table->baseline_image_count;
            if (!valid) {
                break;
            }
            continue;
        }
        if (FleckNemoIsSystemImage(image_name)) {
            continue;
        }
        char canonical_image[PATH_MAX];
        if (!FleckNemoCanonicalPath(image_name, canonical_image)) {
            valid = index < table->baseline_image_count;
            if (!valid) {
                break;
            }
            continue;
        }
        if (FleckNemoIsSystemImage(canonical_image)) {
            continue;
        }
        const int expected_index =
            FleckNemoExpectedIndex(table, canonical_image);
        if (expected_index >= 0) {
            if (!FleckNemoSameIdentity(
                    canonical_image, &table->expected_identities[expected_index])) {
                valid = 0;
                break;
            }
            seen[expected_index] = 1;
            continue;
        }
        if (index >= table->baseline_image_count ||
            FleckNemoExpectedBasenameIndex(canonical_image) >= 0) {
            valid = 0;
            break;
        }
    }
    for (size_t index = 0; valid && index < count; index++) {
        if (!seen[index] ||
            !FleckNemoSameIdentity(
                table->expected_paths[index], &table->expected_identities[index])) {
            valid = 0;
        }
    }
    free(seen);
    return valid;
}

static inline int FleckNemoResolveAllSymbols(
    FleckNemoSymbolTable* table, const char* path) {
    return
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_create",
                               &table->create, sizeof(table->create)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_destroy",
                               &table->destroy, sizeof(table->destroy)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_streaming_recognize",
                               &table->stream_open, sizeof(table->stream_open)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_stream_push_f32",
                               &table->stream_push, sizeof(table->stream_push)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_stream_finish",
                               &table->stream_finish, sizeof(table->stream_finish)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_stream_next",
                               &table->stream_next, sizeof(table->stream_next)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_stream_close",
                               &table->stream_close, sizeof(table->stream_close)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_result_is_final",
                               &table->result_is_final, sizeof(table->result_is_final)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_result_transcript",
                               &table->result_transcript, sizeof(table->result_transcript)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_result_destroy",
                               &table->result_destroy, sizeof(table->result_destroy)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_version",
                               &table->version, sizeof(table->version)) &&
        FleckNemoResolveSymbol(table->handle, path, "nemo_speech_asr_last_error",
                               &table->last_error, sizeof(table->last_error));
}

static inline void FleckNemoCloseDependencies(FleckNemoSymbolTable* table) {
    if (table == NULL || table->dependency_handles == NULL) {
        return;
    }
    for (size_t index = table->dependency_count; index > 0; index--) {
        if (table->dependency_handles[index - 1] != NULL) {
            dlclose(table->dependency_handles[index - 1]);
        }
    }
    free(table->dependency_handles);
    table->dependency_handles = NULL;
    table->dependency_count = 0;
}

static inline void FleckNemoCloseVerified(void* opaque_table) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL) {
        return;
    }
    void* handle = table->handle;
    table->handle = NULL;
    if (handle != NULL) {
        dlclose(handle);
    }
    FleckNemoCloseDependencies(table);
    FleckNemoClearExpectedPaths(table);
    free(table);
}

static inline void* FleckNemoOpenVerified(const char* path) {
    if (path == NULL) {
        return NULL;
    }
    FleckNemoWriteOpenProbe();

    const uint32_t baseline_image_count = _dyld_image_count();

    void* handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        return NULL;
    }
    FleckNemoSymbolTable* table =
        (FleckNemoSymbolTable*)calloc(1, sizeof(FleckNemoSymbolTable));
    if (table == NULL) {
        dlclose(handle);
        return NULL;
    }
    table->handle = handle;
    table->baseline_image_count = baseline_image_count;
    if (!FleckNemoResolveAllSymbols(table, path)) {
        FleckNemoCloseVerified(table);
        return NULL;
    }
    return table;
}

static inline void* FleckNemoOpenRuntimeVerified(
    const char* library_path, const char* snapshot_root) {
    if (library_path == NULL || snapshot_root == NULL) {
        return NULL;
    }
    char canonical_library[PATH_MAX];
    char canonical_root[PATH_MAX];
    char expected_library[PATH_MAX];
    char canonical_expected_library[PATH_MAX];
    if (!FleckNemoCanonicalPath(library_path, canonical_library) ||
        !FleckNemoCanonicalPath(snapshot_root, canonical_root) ||
        !FleckNemoJoinPath(
            canonical_root,
            FleckNemoRuntimeLibraryNames[FleckNemoRuntimeLibraryCount() - 1],
            expected_library) ||
        !FleckNemoCanonicalPath(expected_library, canonical_expected_library) ||
        strcmp(canonical_library, canonical_expected_library) != 0) {
        return NULL;
    }

    FleckNemoWriteOpenProbe();
    FleckNemoSymbolTable* table =
        (FleckNemoSymbolTable*)calloc(1, sizeof(FleckNemoSymbolTable));
    if (table == NULL) {
        return NULL;
    }
    table->baseline_image_count = _dyld_image_count();
    if (!FleckNemoSetExpectedRoot(table, canonical_root)) {
        FleckNemoCloseVerified(table);
        return NULL;
    }

    const size_t dependency_count = FleckNemoRuntimeLibraryCount() - 1;
    table->dependency_handles =
        (void**)calloc(dependency_count, sizeof(void*));
    if (table->dependency_handles == NULL) {
        FleckNemoCloseVerified(table);
        return NULL;
    }
    for (size_t index = 0; index < dependency_count; index++) {
        void* dependency =
            dlopen(table->expected_paths[index], RTLD_NOW | RTLD_GLOBAL);
        if (dependency == NULL) {
            FleckNemoCloseVerified(table);
            return NULL;
        }
        table->dependency_handles[index] = dependency;
        table->dependency_count = index + 1;
    }

    table->handle = dlopen(
        table->expected_paths[dependency_count], RTLD_NOW | RTLD_LOCAL);
    if (table->handle == NULL) {
        FleckNemoCloseVerified(table);
        return NULL;
    }
    if (!FleckNemoResolveAllSymbols(table, table->expected_paths[dependency_count])) {
        FleckNemoCloseVerified(table);
        return NULL;
    }
    if (FleckNemoVerifyRuntimeProvenance(table, canonical_root) == 0) {
        FleckNemoCloseVerified(table);
        return NULL;
    }
    return table;
}

static inline void* FleckNemoCreateRecognizer(
    void* opaque_table, const char* model_path, int32_t gpu) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL || table->create == NULL || model_path == NULL) {
        return NULL;
    }

    nemo_speech_asr_backend_config backend;
    memset(&backend, 0, sizeof(backend));
    backend.size = sizeof(backend);
    backend.gpu = gpu;

    nemo_speech_asr_model_config model;
    memset(&model, 0, sizeof(model));
    model.size = sizeof(model);
    model.path = model_path;

    nemo_speech_asr_streaming_config streaming;
    memset(&streaming, 0, sizeof(streaming));
    streaming.size = sizeof(streaming);
    streaming.chunk_size = 0.16f;
    streaming.rnnt_right_context = -1;

    nemo_speech_asr_recognizer_config config;
    memset(&config, 0, sizeof(config));
    config.size = sizeof(config);
    config.backend = &backend;
    config.model = &model;
    config.streaming = &streaming;

    nemo_speech_asr_recognizer* recognizer = NULL;
    if (table->create(&config, &recognizer) != NEMO_SPEECH_ASR_OK) {
        return NULL;
    }
    return recognizer;
}

static inline void FleckNemoDestroyRecognizer(
    void* opaque_table, void* opaque_recognizer) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table != NULL && table->destroy != NULL && opaque_recognizer != NULL) {
        table->destroy((nemo_speech_asr_recognizer*)opaque_recognizer);
    }
}

static inline void* FleckNemoCreateStream(
    void* opaque_table, void* opaque_recognizer,
    const char* request_id, const char* language_code) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL || table->stream_open == NULL || opaque_recognizer == NULL) {
        return NULL;
    }

    nemo_speech_asr_recognition_options options;
    memset(&options, 0, sizeof(options));
    options.size = sizeof(options);
    options.request_id = request_id;
    options.language_code = language_code;
    options.interim_results = true;
    options.max_alternatives = 1;

    nemo_speech_asr_stream* stream = NULL;
    if (table->stream_open(
            (nemo_speech_asr_recognizer*)opaque_recognizer, &options, &stream) !=
        NEMO_SPEECH_ASR_OK) {
        return NULL;
    }
    return stream;
}

static inline int FleckNemoPush(
    void* opaque_table, void* opaque_stream,
    const float* samples, size_t sample_count, int32_t sample_rate) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL || table->stream_push == NULL || opaque_stream == NULL) {
        return (int)NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    }
    return (int)table->stream_push(
        (nemo_speech_asr_stream*)opaque_stream, samples, sample_count, sample_rate);
}

static inline int FleckNemoFinish(void* opaque_table, void* opaque_stream) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table == NULL || table->stream_finish == NULL || opaque_stream == NULL) {
        return (int)NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    }
    return (int)table->stream_finish((nemo_speech_asr_stream*)opaque_stream);
}

static inline int FleckNemoNext(
    void* opaque_table, void* opaque_stream, void** result_out) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (result_out != NULL) {
        *result_out = NULL;
    }
    if (table == NULL || table->stream_next == NULL || opaque_stream == NULL ||
        result_out == NULL) {
        return (int)NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    }
    return (int)table->stream_next(
        (nemo_speech_asr_stream*)opaque_stream,
        (nemo_speech_asr_result**)result_out);
}

static inline void FleckNemoCloseStream(void* opaque_table, void* opaque_stream) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table != NULL && table->stream_close != NULL && opaque_stream != NULL) {
        table->stream_close((nemo_speech_asr_stream*)opaque_stream);
    }
}

static inline int FleckNemoIsFinal(void* opaque_table, void* opaque_result) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    return table != NULL && table->result_is_final != NULL && opaque_result != NULL &&
           table->result_is_final((nemo_speech_asr_result*)opaque_result);
}

static inline const char* FleckNemoTranscript(
    void* opaque_table, void* opaque_result) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    return table == NULL || table->result_transcript == NULL || opaque_result == NULL
               ? NULL
               : table->result_transcript((nemo_speech_asr_result*)opaque_result, 0);
}

static inline void FleckNemoDestroyResult(void* opaque_table, void* opaque_result) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    if (table != NULL && table->result_destroy != NULL && opaque_result != NULL) {
        table->result_destroy((nemo_speech_asr_result*)opaque_result);
    }
}

static inline const char* FleckNemoVersion(void* opaque_table) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    return table == NULL || table->version == NULL ? NULL : table->version();
}

static inline const char* FleckNemoLastError(void* opaque_table) {
    FleckNemoSymbolTable* table = (FleckNemoSymbolTable*)opaque_table;
    return table == NULL || table->last_error == NULL ? NULL : table->last_error();
}

#endif
