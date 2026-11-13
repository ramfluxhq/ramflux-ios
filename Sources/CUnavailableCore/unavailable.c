// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// No database, transport, accounts or fixtures. Absent Rust is always UnsupportedVersion.
#include "../CRamflux/include/ramflux_sdk.h"
#include <stdlib.h>
// Tests supply strong fixture definitions; shipped source builds only have this refusing provider.
#define RF_UNAVAILABLE __attribute__((weak))
RF_UNAVAILABLE int32_t ramflux_v2_negotiate(uint32_t major, uint32_t minor, struct RamfluxBuffer **out) {
    (void)major; (void)minor; if(out)*out=NULL; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_client_open(const uint8_t *json, size_t len, uint64_t *out) {
    (void)json; (void)len; if(out)*out=0; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_client_close(uint64_t h) { (void)h; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_client_release(uint64_t h) { (void)h; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_execute(uint64_t h, const uint8_t *json, size_t len, uint64_t *out) {
    (void)h; (void)json; (void)len; if(out)*out=0; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_operation_poll(uint64_t h, uint64_t op, struct RamfluxBuffer **out) {
    (void)h; (void)op; if(out)*out=NULL; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_operation_cancel(uint64_t h, uint64_t op) { (void)h; (void)op; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_operation_release(uint64_t h, uint64_t op) { (void)h; (void)op; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_event_poll(uint64_t h, struct RamfluxBuffer **out) { (void)h; if(out)*out=NULL; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_event_reset(uint64_t h, uint64_t generation) { (void)h; (void)generation; return 3; }
RF_UNAVAILABLE void ramflux_v2_buffer_free(struct RamfluxBuffer *buffer) {
    if(!buffer)return;
    volatile uint8_t *bytes=buffer->ptr;
    for(size_t i=0;i<buffer->len;i++)bytes[i]=0;
    free(buffer->ptr);free(buffer);
}
