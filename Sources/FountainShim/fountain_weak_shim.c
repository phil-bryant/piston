#include <stdbool.h>
#include <stddef.h>

typedef struct FountainUploadBatch {
    char *batch_id;
    char *json_payload;
    size_t json_payload_length;
} FountainUploadBatch;

__attribute__((weak))
bool FountainCreateUploadBatch(
    size_t max_events,
    size_t max_bytes,
    FountainUploadBatch *out_batch
) {
    (void)max_events;
    (void)max_bytes;
    (void)out_batch;
    return false;
}

__attribute__((weak))
void FountainMarkUploadBatchSucceeded(const char *batch_id) {
    (void)batch_id;
}

__attribute__((weak))
void FountainMarkUploadBatchFailed(
    const char *batch_id,
    int http_status,
    const char *error_message
) {
    (void)batch_id;
    (void)http_status;
    (void)error_message;
}

__attribute__((weak))
void FountainFreeUploadBatch(FountainUploadBatch *batch) {
    (void)batch;
}
