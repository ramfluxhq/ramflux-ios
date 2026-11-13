// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#ifndef RF_SECURE_BUFFER_H
#define RF_SECURE_BUFFER_H
#include "ramflux_sdk.h"
void rf_secure_zero(void *pointer, size_t length);
void rf_buffer_wipe_free(struct RamfluxBuffer *buffer);
#endif
