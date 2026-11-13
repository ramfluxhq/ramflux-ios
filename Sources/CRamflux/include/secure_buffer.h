// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#ifndef RF_SECURE_BUFFER_H
#define RF_SECURE_BUFFER_H
#include "ramflux_sdk.h"
const char *rf_completion_refusal_reason(const struct RamfluxBuffer *buffer);
int rf_completion_code(const struct RamfluxBuffer *buffer, int32_t *code);
void rf_secure_zero(void *pointer, size_t length);
void rf_buffer_wipe_free(struct RamfluxBuffer *buffer);
#endif
