// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#include "secure_buffer.h"
#include <limits.h>
#include <string.h>

// SDK completions are serialized with their numeric code first. Inspect only this
// bounded envelope prefix; the secret response payload is never decoded or copied here.
int rf_completion_code(const struct RamfluxBuffer *buffer, int32_t *code) {
    if (!buffer || !code || !buffer->ptr || buffer->len > 1048576) return 0;
    const unsigned char *p = buffer->ptr;
    size_t n = buffer->len < 128 ? buffer->len : 128, i = 0;
    while (i < n && (p[i] == ' ' || p[i] == '\n' || p[i] == '\r' || p[i] == '\t')) ++i;
    if (i == n || p[i++] != '{') return 0;
    while (i < n && p[i] == ' ') ++i;
    if (n - i < 6 || memcmp(p + i, "\"code\"", 6) != 0) return 0;
    i += 6;
    while (i < n && p[i] == ' ') ++i;
    if (i == n || p[i++] != ':') return 0;
    while (i < n && p[i] == ' ') ++i;
    int64_t value = 0; size_t digits = 0;
    while (i < n && p[i] >= '0' && p[i] <= '9') {
        value = value * 10 + (p[i++] - '0');
        if (++digits > 10 || value > INT32_MAX) return 0;
    }
    while (i < n && p[i] == ' ') ++i;
    if (!digits || i == n || (p[i] != ',' && p[i] != '}')) return 0;
    *code = (int32_t)value; return 1;
}
