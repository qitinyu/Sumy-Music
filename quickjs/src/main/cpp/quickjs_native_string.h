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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_STRING_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_STRING_H

#include "quickjs_native_value.h"

class QuickJSNativeString : public QuickJSNativeValue, public NativeString {
public:
    QuickJSNativeString(QuickJSNativeEngine* engine, JSValue value);
    QuickJSNativeString(QuickJSNativeEngine* engine, JSAtom value);
    QuickJSNativeString(QuickJSNativeEngine* engine, const char* value, size_t length);
    QuickJSNativeString(QuickJSNativeEngine* engine, const char16_t* value, size_t length);
    ~QuickJSNativeString() override;

    void* GetInterface(int interfaceId) override;

    void GetCString(char* buffer, size_t size, size_t* length) override;
    void GetCString16(char16_t* buffer, size_t size, size_t* length) override;
    size_t GetLength() override;
    size_t EncodeWriteUtf8(char* buffer, size_t bufferSize, int32_t* nchars) override;

private:
    char16_t* Utf8ToUtf16(const char* utf8Str, size_t u8len, char16_t* u16str, size_t u16len);
    static inline size_t Utf8CodePointLen(uint8_t ch);
    uint32_t Utf8ToUtf32CodePoint(const char* src, size_t length);
    static inline void Utf8ShiftAndMask(uint32_t* codePoint, const uint8_t byte);
    int Utf8ToUtf16Length(const char* str8, size_t str8Len);
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_STRING_H */
