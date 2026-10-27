#pragma once
#include <stddef.h>
#include <stdint.h>
typedef struct {
    int status;
    uint8_t *data;
    size_t count;
    char *headers;
    unsigned long error;
} CRHTTPResponse;
CRHTTPResponse cr_http(const char *url, const char *method, const char *headers,
                      const uint8_t *body, size_t count, int timeout_ms);
void cr_http_free(CRHTTPResponse *response);
int cr_digest(const uint8_t *input, size_t count, const uint8_t *key, size_t key_count,
              int kind, uint8_t *output, size_t output_count);
void cr_open_url(const char *url);
void cr_window_topmost(int enabled);
