// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#ifndef RF_FIXTURE_H
#define RF_FIXTURE_H
#include <stdint.h>
#include <stddef.h>
void rf_fixture_reset(void);
void rf_fixture_set_pending(int pending);
void rf_fixture_set_close_code(int code);
void rf_fixture_set_terminal(const char *json);
void rf_fixture_set_event(const char *json);
void rf_fixture_set_event_status(int status);
size_t rf_fixture_copy_request(char *out, size_t capacity);
int rf_fixture_submissions(void);
int rf_fixture_cancellations(void);
int rf_fixture_releases(void);
int rf_fixture_live_buffers(void);
#endif
// Additional ABI-faithfulness controls.
void rf_fixture_set_open_code(int code);
void rf_fixture_set_secret_terminal(int enabled);
void rf_fixture_set_methods(const char *json);
int rf_fixture_opens(void);
int rf_fixture_closes(void);
int rf_fixture_resets(void);
int rf_fixture_subscription_cancels(void);
int rf_fixture_subscription_releases(void);
