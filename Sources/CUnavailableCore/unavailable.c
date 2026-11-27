// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// No database, transport, accounts or fixtures. Absent Rust is always UnsupportedVersion.
#include "../CRamflux/include/ramflux_sdk.h"
#include "../CRamflux/include/ramflux_card.h"
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
RF_UNAVAILABLE int32_t ramflux_v2_wake_fetch(const uint8_t *config, size_t config_len, const struct RamfluxV2CustodyProvider *provider, struct RamfluxBuffer **out) {
    (void)config; (void)config_len; (void)provider; if(out)*out=NULL; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_shared_snapshot(const uint8_t *config, size_t config_len, const struct RamfluxV2CustodyProvider *provider, struct RamfluxBuffer **out) {
    (void)config; (void)config_len; (void)provider; if(out)*out=NULL; return 3;
}
RF_UNAVAILABLE int32_t ramflux_v2_client_suspend(uint64_t h) { (void)h; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_client_resume(uint64_t h) { (void)h; return 3; }
RF_UNAVAILABLE int32_t ramflux_v2_username_authorize(uint64_t h, const uint8_t *request, size_t request_len, const uint8_t *phrase, size_t phrase_len, struct RamfluxBuffer **out_signed, struct RamfluxBuffer **out_error) {
    (void)h; (void)request; (void)request_len; (void)phrase; (void)phrase_len; if(out_signed)*out_signed=NULL; if(out_error)*out_error=NULL; return 3;
}
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

RF_UNAVAILABLE int32_t ramflux_v2_client_open_with_custody(const uint8_t *json, size_t len, const struct RamfluxV2CustodyProvider *provider, uint64_t *out) {
    (void)provider; return ramflux_v2_client_open(json,len,out);
}

// Gallery-only trust package (RAMFLUX_CARD_GALLERY test builds): absent in source-only builds.
RF_UNAVAILABLE int32_t ramflux_v2_card_trust_package(struct RamfluxBuffer **out) {
    if(out)*out=NULL; return 6;
}

// Renderer (card-runtime) refusals: every card call is inactive (status 6) and emits no callback.
RF_UNAVAILABLE uint32_t ramflux_card_abi_version(void) { return 0; }
RF_UNAVAILABLE int32_t ramflux_card_open(const RamfluxCardOpen *input, RamfluxCardCallback callback, void *user, uint64_t *out) {
    (void)input; (void)callback; (void)user; if(out)*out=0; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_tree(uint64_t session, RamfluxCardCallback callback, void *user) {
    (void)session; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_update(uint64_t session, RamfluxCardBytes input, RamfluxCardCallback callback, void *user) {
    (void)session; (void)input; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_present(uint64_t session, RamfluxCardBytes input, RamfluxCardCallback callback, void *user) {
    (void)session; (void)input; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_event(uint64_t session, RamfluxCardBytes input, RamfluxCardCallback callback, void *user) {
    (void)session; (void)input; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_suspend(uint64_t session, RamfluxCardCallback callback, void *user) {
    (void)session; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_resume(uint64_t session, RamfluxCardCallback callback, void *user) {
    (void)session; (void)callback; (void)user; return 6;
}
RF_UNAVAILABLE int32_t ramflux_card_dispose(uint64_t session) { (void)session; return 6; }
