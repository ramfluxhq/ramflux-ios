// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
// Test-only ABI implementation. Release has the SDK's cancellation semantics.
#include "fixture.h"
#include "generated_methods.h"
#include "../../Sources/CRamflux/include/ramflux_sdk.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define CAP 1048576
#define MAX_OPS 256
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static char request[CAP+1], terminal[CAP+1], event[CAP+1], methods[65536];
static size_t request_len;
static int pending, close_code, open_code, event_status, submitted, cancellations, releases, buffers;
static int opens, closes, resets, subscription_cancels, subscription_releases, secret_terminal;
static uint64_t client_serial, live_client, subscription;
struct operation { int cancelled, released, is_subscription; };
static struct operation operations[MAX_OPS];
static void test_zero(void *p,size_t n) { volatile unsigned char *b=p;while(n--)*b++=0; }
static struct RamfluxBuffer *output(const char *s) {
    size_t n = strlen(s);
    struct RamfluxBuffer *b = malloc(sizeof(*b));
    if (!b) abort();
    b->ptr = malloc(n); if (n && !b->ptr) abort();
    memcpy(b->ptr,s,n);b->len=n;buffers++;return b;
}
static void text_copy(char *dest,size_t cap,const char *src) { size_t n=strlen(src);if(n>=cap)abort();memcpy(dest,src,n+1); }
void rf_fixture_reset(void) {
    pthread_mutex_lock(&lock);
    test_zero(request,sizeof request);request_len=0;
    text_copy(terminal,sizeof terminal,"{\"code\":0,\"response\":{\"kind\":\"response\",\"body\":{}}}");
    text_copy(methods,sizeof methods,RF_FIXTURE_METHODS_JSON);
    test_zero(event,sizeof event);test_zero(operations,sizeof operations);
    pending=close_code=open_code=event_status=submitted=cancellations=releases=0;
    opens=closes=resets=subscription_cancels=subscription_releases=secret_terminal=0;
    live_client=subscription=0;
    pthread_mutex_unlock(&lock);
}
#define SETTER(name,field) void name(int v) { pthread_mutex_lock(&lock);field=v;pthread_mutex_unlock(&lock); }
SETTER(rf_fixture_set_pending,pending)
SETTER(rf_fixture_set_close_code,close_code)
SETTER(rf_fixture_set_open_code,open_code)
SETTER(rf_fixture_set_event_status,event_status)
SETTER(rf_fixture_set_secret_terminal,secret_terminal)
#define TEXT_SETTER(name,field) void name(const char *v) { pthread_mutex_lock(&lock);text_copy(field,sizeof field,v);pthread_mutex_unlock(&lock); }
TEXT_SETTER(rf_fixture_set_terminal,terminal)
TEXT_SETTER(rf_fixture_set_event,event)
TEXT_SETTER(rf_fixture_set_methods,methods)
size_t rf_fixture_copy_request(char *out,size_t cap) { pthread_mutex_lock(&lock);size_t n=request_len<cap?request_len:cap;memcpy(out,request,n);pthread_mutex_unlock(&lock);return n; }
#define GETTER(name,value) int name(void) { pthread_mutex_lock(&lock);int v=value;pthread_mutex_unlock(&lock);return v; }
GETTER(rf_fixture_submissions,submitted)
GETTER(rf_fixture_cancellations,cancellations)
GETTER(rf_fixture_releases,releases)
GETTER(rf_fixture_live_buffers,buffers)
GETTER(rf_fixture_opens,opens)
GETTER(rf_fixture_closes,closes)
GETTER(rf_fixture_resets,resets)
GETTER(rf_fixture_subscription_cancels,subscription_cancels)
GETTER(rf_fixture_subscription_releases,subscription_releases)
int32_t ramflux_v2_negotiate(uint32_t major,uint32_t minor,struct RamfluxBuffer **out) {
    *out=NULL;if(major!=2 || minor!=0)return 3;
    pthread_mutex_lock(&lock);
    const char *prefix="{\"abi_major\":2,\"abi_minor\":0,\"bus_protocol\":\"ramflux.local_bus.v1\",\"message_descriptor_blake3\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"methods\":";
    size_t n=strlen(prefix)+strlen(methods)+2;
    char *json=malloc(n);if(!json)abort();strcpy(json,prefix);strcat(json,methods);strcat(json,"}");
    *out=output(json);free(json);pthread_mutex_unlock(&lock);return 0;
}
int32_t ramflux_v2_client_open(const uint8_t *config,size_t len,uint64_t *out) {
    (void)config;(void)len;*out=0;pthread_mutex_lock(&lock);opens++;
    int code=open_code;open_code=0;
    if(!code) { live_client=++client_serial;*out=live_client; }
    pthread_mutex_unlock(&lock);return code;
}
int32_t ramflux_v2_client_close(uint64_t h) {
    pthread_mutex_lock(&lock);closes++;
    int code=close_code;
    if(!code && live_client==h) { live_client=0;subscription=0; }
    pthread_mutex_unlock(&lock);return code;
}
int32_t ramflux_v2_execute(uint64_t h,const uint8_t *input,size_t len,uint64_t *out) {
    *out=0;if(len>CAP)return 1;pthread_mutex_lock(&lock);
    if(h!=live_client || !h) { pthread_mutex_unlock(&lock);return 26; }
    if(submitted+1>=MAX_OPS) { pthread_mutex_unlock(&lock);return 15; }
    memcpy(request,input,len);request[len]=0;request_len=len;
    int is_sub=strstr(request,"\"method\":\"subscription.open\"")!=NULL || strstr(request,"\"method\":\"bus.subscribe\"")!=NULL;
    if(is_sub && subscription) { pthread_mutex_unlock(&lock);return 15; }
    submitted++;operations[submitted]=(struct operation){0,0,is_sub};*out=(uint64_t)submitted;
    if(is_sub)subscription=*out;
    pthread_mutex_unlock(&lock);return 0;
}
int32_t ramflux_v2_operation_poll(uint64_t h,uint64_t op,struct RamfluxBuffer **out) {
    *out=NULL;pthread_mutex_lock(&lock);
    if(h!=live_client || !h || op>=MAX_OPS || operations[op].released) { pthread_mutex_unlock(&lock);return 26; }
    int code=0;
    if(operations[op].cancelled)*out=output("{\"code\":25,\"effects\":\"unknown\"}");
    else if(pending && !operations[op].is_subscription)code=24;
    else { *out=output(terminal);if(secret_terminal) { test_zero(terminal,sizeof terminal);secret_terminal=0; } }
    pthread_mutex_unlock(&lock);return code;
}
static void cancel_operation(uint64_t op) {
    if(op && op<MAX_OPS) {
        if(operations[op].is_subscription && subscription==op) { subscription=0;subscription_cancels++; }
        operations[op].cancelled=1;
    }
}
int32_t ramflux_v2_operation_cancel(uint64_t h,uint64_t op) {
    (void)h;pthread_mutex_lock(&lock);cancellations++;cancel_operation(op);pthread_mutex_unlock(&lock);return 0;
}
int32_t ramflux_v2_operation_release(uint64_t h,uint64_t op) {
    (void)h;pthread_mutex_lock(&lock);releases++;
    if(op && op<MAX_OPS) {
        cancel_operation(op);
        if(operations[op].is_subscription)subscription_releases++;
        operations[op].released=1;
    }
    pthread_mutex_unlock(&lock);return 0;
}
int32_t ramflux_v2_event_poll(uint64_t h,struct RamfluxBuffer **out) {
    *out=NULL;pthread_mutex_lock(&lock);int code=event_status;
    if(!h || h!=live_client || !subscription)code=26;
    else if(!code && event[0]) { *out=output(event);test_zero(event,sizeof event); }
    else if(!code)code=24;
    pthread_mutex_unlock(&lock);return code;
}
int32_t ramflux_v2_event_reset(uint64_t h) {
    pthread_mutex_lock(&lock);
    if(h!=live_client || !h || subscription) { pthread_mutex_unlock(&lock);return 1; }
    test_zero(event,sizeof event);event_status=0;resets++;pthread_mutex_unlock(&lock);return 0;
}
void ramflux_v2_buffer_free(struct RamfluxBuffer *b) {
    if(!b)return;pthread_mutex_lock(&lock);test_zero(b->ptr,b->len);free(b->ptr);free(b);buffers--;pthread_mutex_unlock(&lock);
}
