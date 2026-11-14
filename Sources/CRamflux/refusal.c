// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#include "secure_buffer.h"
#include <string.h>

// Borrowed spans only: never copy a secret-marked frame or return peer-controlled text.
struct span { const unsigned char *p; size_t n; };
struct parser { const unsigned char *p; size_t n, i; };
static void ws(struct parser *s) {
    while (s->i < s->n && strchr(" \r\n\t", s->p[s->i]) && s->p[s->i]) ++s->i;
}
static int string(struct parser *s, struct span *out) {
    if (s->i >= s->n || s->p[s->i++] != '"') return 0;
    size_t start = s->i;
    while (s->i < s->n) {
        unsigned char c = s->p[s->i++];
        if (c == '"') { *out = (struct span){s->p + start, s->i - start - 1}; return 1; }
        if (c < 32) return 0;
        if (c == '\\') {
            if (s->i >= s->n) return 0;
            c = s->p[s->i++];
            if (c == 'u') {
                for (unsigned j = 0; j < 4; ++j) {
                    if (s->i >= s->n || !strchr("0123456789abcdefABCDEF", s->p[s->i]) || !s->p[s->i]) return 0;
                    ++s->i;
                }
            } else if (!strchr("\"\\/bfnrt", c) || !c) return 0;
        }
    }
    return 0;
}
static int skip(struct parser *s, unsigned depth) {
    if (depth > 64) return 0;
    ws(s); if (s->i >= s->n) return 0;
    unsigned char c = s->p[s->i];
    if (c == '"') { struct span ignored; return string(s, &ignored); }
    if (c == '{' || c == '[') {
        unsigned char end = c == '{' ? '}' : ']'; ++s->i; ws(s);
        if (s->i < s->n && s->p[s->i] == end) { ++s->i; return 1; }
        for (;;) {
            if (c == '{') { struct span key; if (!string(s, &key)) return 0; ws(s); if (s->i >= s->n || s->p[s->i++] != ':') return 0; }
            if (!skip(s, depth + 1)) return 0;
            ws(s); if (s->i >= s->n) return 0;
            unsigned char next = s->p[s->i++];
            if (next == end) return 1;
            if (next != ',') return 0;
            ws(s);
        }
    }
    size_t start = s->i;
    while (s->i < s->n && !strchr(",]} \r\n\t", s->p[s->i]) && s->p[s->i]) ++s->i;
    return s->i > start;
}
static int equal(struct span s, const char *literal) { return s.n == strlen(literal) && memcmp(s.p, literal, s.n) == 0; }
static int field(struct span object, const char *name, struct span *out) {
    struct parser s = {object.p, object.n, 0}; ws(&s);
    if (s.i >= s.n || s.p[s.i++] != '{') return 0;
    int found = 0;
    for (;;) {
        ws(&s); if (s.i >= s.n) return 0;
        if (s.p[s.i] == '}') return found;
        struct span key; if (!string(&s, &key)) return 0;
        ws(&s); if (s.i >= s.n || s.p[s.i++] != ':') return 0;
        ws(&s); size_t start = s.i;
        if (!skip(&s, 0)) return 0;
        if (equal(key, name)) {
            if (found) return 0;
            *out = (struct span){s.p + start, s.i - start}; found = 1;
        }
        ws(&s); if (s.i >= s.n) return 0;
        if (s.p[s.i] == '}') return found;
        if (s.p[s.i++] != ',') return 0;
    }
}
const char *rf_completion_refusal_reason(const struct RamfluxBuffer *buffer) {
    int32_t code = 0;
    if (!rf_completion_code(buffer, &code) || code == 0) return NULL;
    struct span response, error, encoded, reason;
    struct parser whole = {buffer->ptr, buffer->len, 0};
    if (!skip(&whole, 0)) return NULL;
    ws(&whole); if (whole.i != whole.n) return NULL;
    struct span root = {buffer->ptr, buffer->len};
    if (!field(root, "response", &response) || !field(response, "error", &error) || !field(error, "reason_code", &encoded)) return NULL;
    struct parser s = {encoded.p, encoded.n, 0};
    if (!string(&s, &reason) || s.i != s.n) return NULL;
    static const char *const allowed[] = {"vault_permission", "vault_locked", "vault_missing", "vault_corrupt", "vault_busy", "vault_primary_unavailable"};
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); ++i) if (equal(reason, allowed[i])) return allowed[i];
    return NULL;
}
static const char *allow_typed(struct span reason) {
    static const char *const allowed[] = {
        "invalid_argument", "invalid_json", "peer_upgrade_required", "storage_capacity",
        "schema_reset_required", "resync_required", "edit_conflict", "not_authorized",
        "target_not_found", "target_deleted", "payload_too_large", "rate_limited",
        "ephemeral_unavailable", "crypto_failure", "not_connected", "internal"
    };
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); ++i) if (equal(reason, allowed[i])) return allowed[i];
    return NULL;
}
static const char *named_string(struct span object, const char *name) {
    struct span encoded, value;
    if (!field(object, name, &encoded)) return NULL;
    struct parser s = {encoded.p, encoded.n, 0};
    if (!string(&s, &value) || s.i != s.n) return NULL;
    return allow_typed(value);
}
const char *rf_completion_typed_name(const struct RamfluxBuffer *buffer) {
    int32_t code = 0;
    if (!buffer || !rf_completion_code(buffer, &code) || code == 0 || !buffer->ptr) return NULL;
    struct parser whole = {buffer->ptr, buffer->len, 0};
    if (!skip(&whole, 0)) return NULL;
    ws(&whole); if (whole.i != whole.n) return NULL;
    struct span root = {buffer->ptr, buffer->len}, response, nested;
    if (!field(root, "response", &response)) return NULL;
    if (field(response, "body", &nested)) {
        const char *name = named_string(nested, "name");
        if (name) return name;
    }
    if (!field(response, "error", &nested)) return NULL;
    const char *name = named_string(nested, "name");
    if (name) return name;
    return named_string(nested, "code");
}
