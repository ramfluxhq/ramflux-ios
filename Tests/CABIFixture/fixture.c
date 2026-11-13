// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// Test-only ABI implementation. Never linked by the package's library product.
#include "fixture.h"
#include "../../Sources/CRamflux/include/ramflux_sdk.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static char request[1048576];
static size_t request_len;
static char terminal[16384], event[16384];
static int pending, close_code, event_status, submitted, cancellations, releases, buffers;
static int cancelled;
static void test_zero(void *p,size_t n) { volatile unsigned char *b=p;while(n--)*b++=0; }
static struct RamfluxBuffer *output(const char *s) {
    size_t n = strlen(s);
    struct RamfluxBuffer *b = malloc(sizeof(*b));
    if (!b) abort();
    b->ptr = malloc(n); if (n && !b->ptr) abort();
    memcpy(b->ptr, s, n); b->len = n; buffers++;
    return b;
}
void rf_fixture_reset(void) {
    pthread_mutex_lock(&lock);
    test_zero(request, sizeof request); request_len = 0;
    strcpy(terminal, "{\"code\":0,\"response\":{\"kind\":\"response\",\"body\":{}}}");
    event[0] = 0; pending = close_code = event_status = submitted = cancellations = releases = cancelled = 0;
    pthread_mutex_unlock(&lock);
}
void rf_fixture_set_pending(int v) { pthread_mutex_lock(&lock); pending = v; pthread_mutex_unlock(&lock); }
void rf_fixture_set_close_code(int v) { pthread_mutex_lock(&lock); close_code = v; pthread_mutex_unlock(&lock); }
void rf_fixture_set_event_status(int v) { pthread_mutex_lock(&lock); event_status = v; pthread_mutex_unlock(&lock); }
void rf_fixture_set_terminal(const char *v) { pthread_mutex_lock(&lock); strncpy(terminal,v,sizeof terminal-1); terminal[sizeof terminal-1]=0; pthread_mutex_unlock(&lock); }
void rf_fixture_set_event(const char *v) { pthread_mutex_lock(&lock); strncpy(event,v,sizeof event-1); event[sizeof event-1]=0; pthread_mutex_unlock(&lock); }
size_t rf_fixture_copy_request(char *out,size_t cap) { pthread_mutex_lock(&lock); size_t n = request_len < cap ? request_len : cap; memcpy(out,request,n); pthread_mutex_unlock(&lock); return n; }
#define GETTER(name,value) int name(void) { pthread_mutex_lock(&lock); int v=value; pthread_mutex_unlock(&lock); return v; }
GETTER(rf_fixture_submissions,submitted)
GETTER(rf_fixture_cancellations,cancellations)
GETTER(rf_fixture_releases,releases)
GETTER(rf_fixture_live_buffers,buffers)
int32_t ramflux_v2_negotiate(uint32_t major,uint32_t minor,struct RamfluxBuffer **out) {
    *out = NULL; if(major!=2 || minor!=0) return 3;
    pthread_mutex_lock(&lock);
    *out=output("{\"abi_major\":2,\"abi_minor\":0,\"bus_protocol\":\"ramflux.local_bus.v1\",\"message_descriptor_blake3\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"methods\":[\"account.list\",\"account.unlock\",\"account.create.begin\",\"account.create.show_once\",\"account.create.hidden_challenge\",\"account.create.confirm\",\"account.create.cancel\",\"subscription.open\"]}");
    pthread_mutex_unlock(&lock); return 0;
}
int32_t ramflux_v2_client_open(const uint8_t *config,size_t len,uint64_t *out) { (void)config;(void)len;*out=1;return 0; }
int32_t ramflux_v2_client_close(uint64_t handle) { (void)handle;pthread_mutex_lock(&lock);int code=close_code;pthread_mutex_unlock(&lock);return code; }
int32_t ramflux_v2_execute(uint64_t h,const uint8_t *input,size_t len,uint64_t *out) {
    (void)h; *out=0; if(len>sizeof request)return 1;
    pthread_mutex_lock(&lock); memcpy(request,input,len);request_len=len;submitted++;cancelled=0;*out=(uint64_t)submitted;
    pthread_mutex_unlock(&lock);return 0;
}
int32_t ramflux_v2_operation_poll(uint64_t h,uint64_t op,struct RamfluxBuffer **out) {
    (void)h;(void)op;*out=NULL;
    pthread_mutex_lock(&lock);
    int code = 0;
    if(cancelled) *out=output("{\"code\":25,\"effects\":\"unknown\"}");
    else if(pending) code=24;
    else *out=output(terminal);
    pthread_mutex_unlock(&lock);return code;
}
int32_t ramflux_v2_operation_cancel(uint64_t h,uint64_t op) { (void)h;(void)op;pthread_mutex_lock(&lock);cancelled=1;cancellations++;pthread_mutex_unlock(&lock);return 0; }
int32_t ramflux_v2_operation_release(uint64_t h,uint64_t op) { (void)h;(void)op;pthread_mutex_lock(&lock);releases++;pthread_mutex_unlock(&lock);return 0; }
int32_t ramflux_v2_event_poll(uint64_t h,struct RamfluxBuffer **out) {
    (void)h;*out=NULL;pthread_mutex_lock(&lock);int code=event_status;
    if(!code && event[0]) { *out=output(event);event[0]=0; }
    else if(!code) code=24;
    pthread_mutex_unlock(&lock);return code;
}
void ramflux_v2_buffer_free(struct RamfluxBuffer *b) {
    if(!b)return;
    pthread_mutex_lock(&lock);test_zero(b->ptr,b->len);free(b->ptr);free(b);buffers--;pthread_mutex_unlock(&lock);
}
