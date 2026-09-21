/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "quickjs_native_string.h"

#include <cstring>

QuickJSNativeString::QuickJSNativeString(QuickJSNativeEngine *engine, JSValue value)
    : QuickJSNativeValue(engine, value) {}

QuickJSNativeString::QuickJSNativeString(QuickJSNativeEngine *engine, JSAtom value)
    : QuickJSNativeString(engine, JS_AtomToString(engine->GetContext(), value)) {}

QuickJSNativeString::QuickJSNativeString(QuickJSNativeEngine *engine, const char *value, size_t length)
    : QuickJSNativeString(engine, JS_NewStringLen(engine->GetContext(), value, length)) {}

QuickJSNativeString::QuickJSNativeString(QuickJSNativeEngine *engine, const char16_t *value, size_t length)
    : QuickJSNativeString(engine,
                          JS_NewString16(engine->GetContext(), reinterpret_cast<const uint16_t *>(value), length)) {}

QuickJSNativeString::~QuickJSNativeString() {}

void *QuickJSNativeString::GetInterface(int interfaceId) {
    return (NativeString::INTERFACE_ID == interfaceId) ? (NativeString *)this : nullptr;
}

void QuickJSNativeString::GetCString(char *buffer, size_t size, size_t *length) {
    const char *str = JS_ToCStringLen(engine_->GetContext(), length, value_);

    if (str == nullptr) {
        // HILOG_ERROR("JS_ToCStringLen return value is null");
        return;
    }

    if (buffer != nullptr && length != nullptr) {
        int ret = strncpy_s(buffer, size, str, *length);
        if (ret != EOK) {
            // HILOG_ERROR("strncpy_s failed");
        }
    }
    JS_FreeCString(engine_->GetContext(), str);
}
void QuickJSNativeString::GetCString16(char16_t *buffer, size_t size, size_t *length) {
    const char *str = JS_ToCStringLen(engine_->GetContext(), length, value_);
    if (str == nullptr) {
        // HILOG_ERROR("JS_ToCStringLen return value is null");
        return;
    }
    if (length != nullptr) {
        auto ret = Utf8ToUtf16Length(str, strlen(str));
        if (ret == -1) {
            // HILOG_ERROR("JS_ToCStringLen length is invalid");
            JS_FreeCString(engine_->GetContext(), str);
            return;
        }
        *length = ret;
        if (buffer != nullptr) {
            memset_s(buffer, sizeof(char16_t) * size, 0x0, sizeof(char16_t) * size);
            Utf8ToUtf16(str, strlen(str), buffer, size);
        }
    }
    JS_FreeCString(engine_->GetContext(), str);
}

size_t QuickJSNativeString::GetLength() {
    size_t length = 0;
    GetCString(nullptr, 0, &length);
    return length;
}

size_t QuickJSNativeString::EncodeWriteUtf8(char *buffer, size_t bufferSize, int32_t *nchars) {
    if (buffer == nullptr || nchars == nullptr) {
        // HILOG_ERROR("buffer is null or nchars is null");
        return 0;
    }

    JSContext *ctx = engine_->GetContext();
    JSValue lengthVal = JS_GetPropertyStr(ctx, value_, "length");
    if (JS_IsException(lengthVal)) {
        // HILOG_ERROR("Failed to obtain the length");
        return 0;
    }
    uint32_t len = 0;
    if (JS_ToUint32(ctx, &len, lengthVal)) {
        JS_FreeValue(ctx, lengthVal);
        // HILOG_ERROR("Cannot convert length to uint32_t");
        return 0;
    }

    size_t pos = 0;
    size_t writableSize = bufferSize;
    uint32_t i = 0;
    for (; i < len; i++) {
        JSValue ch = JS_GetPropertyUint32(ctx, value_, i);
        size_t chLen = 0;
        const char *str = JS_ToCStringLen(ctx, &chLen, ch);
        JS_FreeValue(ctx, ch);
        if (chLen > writableSize) {
            JS_FreeCString(ctx, str);
            break;
        }

        int ret = memcpy_s((buffer + pos), writableSize, str, chLen);
        if (ret != EOK) {
            // HILOG_ERROR("memcpy_s failed");
            JS_FreeCString(ctx, str);
            break;
        }

        writableSize -= chLen;
        pos = bufferSize - writableSize;
        JS_FreeCString(ctx, str);
    }

    *nchars = i;
    JS_FreeValue(ctx, lengthVal);
    return pos;
}

char16_t *QuickJSNativeString::Utf8ToUtf16(const char *utf8Str, size_t u8len, char16_t *u16str, size_t u16len) {
    if (u16len == 0) {
        return u16str;
    }
    const char *u8end = utf8Str + u8len;
    const char *u8cur = utf8Str;
    const char16_t *u16end = u16str + u16len - 1;
    constexpr uint8_t offset = 10;
    char16_t *u16cur = u16str;

    while ((u8cur < u8end) && (u16cur < u16end)) {
        size_t len = Utf8CodePointLen(*u8cur);
        uint32_t codepoint = Utf8ToUtf32CodePoint(u8cur, len);
        // Convert the UTF32 codepoint to one or more UTF16 codepoints
        if (codepoint <= 0xFFFF) {
            // Single UTF16 character
            *u16cur++ = (char16_t)codepoint;
        } else {
            // Multiple UTF16 characters with surrogates
            codepoint = codepoint - 0x10000;
            *u16cur++ = (char16_t)((codepoint >> offset) + 0xD800);
            if (u16cur >= u16end) {
                // Ooops...  not enough room for this surrogate pair.
                return u16cur - 1;
            }
            *u16cur++ = (char16_t)((codepoint & 0x3FF) + 0xDC00);
        }

        u8cur += len;
    }
    return u16cur;
}

size_t QuickJSNativeString::Utf8CodePointLen(uint8_t ch) {
    constexpr uint8_t offset = 3;
    return ((0xe5000000 >> ((ch >> offset) & 0x1e)) & offset) + 1;
}

uint32_t QuickJSNativeString::Utf8ToUtf32CodePoint(const char *src, size_t length) {
    uint32_t unicode = 0;
    constexpr size_t lengthSizeOne = 1;
    constexpr size_t lengthSizeTwo = 2;
    constexpr size_t lengthSizeThree = 3;
    constexpr size_t lengthSizeFour = 4;
    constexpr size_t offsetZero = 0;
    constexpr size_t offsetOne = 1;
    constexpr size_t offsetTwo = 2;
    constexpr size_t offsetThree = 3;
    switch (length) {
    case lengthSizeOne:
        return src[offsetZero];
    case lengthSizeTwo:
        unicode = src[offsetZero] & 0x1f;
        Utf8ShiftAndMask(&unicode, src[offsetOne]);
        return unicode;
    case lengthSizeThree:
        unicode = src[offsetZero] & 0x0f;
        Utf8ShiftAndMask(&unicode, src[offsetOne]);
        Utf8ShiftAndMask(&unicode, src[offsetTwo]);
        return unicode;
    case lengthSizeFour:
        unicode = src[offsetZero] & 0x07;
        Utf8ShiftAndMask(&unicode, src[offsetOne]);
        Utf8ShiftAndMask(&unicode, src[offsetTwo]);
        Utf8ShiftAndMask(&unicode, src[offsetThree]);
        return unicode;
    default:
        return 0xffff;
    }
}

void QuickJSNativeString::Utf8ShiftAndMask(uint32_t *codePoint, const uint8_t byte) {
    *codePoint <<= 6;
    *codePoint |= 0x3F & byte;
}

int QuickJSNativeString::Utf8ToUtf16Length(const char *str8, size_t str8Len) {
    const char *str8end = str8 + str8Len;
    int utf16len = 0;
    while (str8 < str8end) {
        utf16len++;
        size_t u8charlen = Utf8CodePointLen(*str8);
        if (str8 + u8charlen - 1 >= str8end) {
            // HILOG_ERROR("Get str16 length failed because str8 unicode is illegal!");
            return -1;
        }
        uint32_t codepoint = Utf8ToUtf32CodePoint(str8, u8charlen);
        if (codepoint > 0xFFFF) {
            utf16len++; // this will be a surrogate pair in utf16
        }
        str8 += u8charlen;
    }
    if (str8 != str8end) {
        // HILOG_ERROR("Get str16 length failed because str8length is illegal!");
        return -1;
    }
    return utf16len;
}
