// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#include "secure_buffer.h"
#include <string.h>
void rf_secure_zero(void *pointer, size_t length) {
    volatile unsigned char *bytes = pointer;
    while (length--) *bytes++ = 0;
}
void rf_buffer_wipe_free(struct RamfluxBuffer *buffer) {
    if (!buffer) return;
    if (buffer->ptr && buffer->len) rf_secure_zero(buffer->ptr, buffer->len);
    ramflux_v2_buffer_free(buffer);
}
