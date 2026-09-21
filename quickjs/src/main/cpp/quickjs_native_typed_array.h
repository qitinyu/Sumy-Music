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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_TYPED_ARRAY_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_TYPED_ARRAY_H

#include "quickjs_native_object.h"

class QuickJSNativeTypedArray : public QuickJSNativeObject, public NativeTypedArray {
public:
    explicit QuickJSNativeTypedArray(QuickJSNativeEngine* engine, JSValue value);
    QuickJSNativeTypedArray(QuickJSNativeEngine* engine, NativeTypedArrayType type, NativeValue* value, size_t length, size_t offset);
    ~QuickJSNativeTypedArray() override;

    void* GetInterface(int interfaceId) override;

    NativeTypedArrayType GetTypedArrayType() override;
    NativeValue* GetArrayBuffer() override;
    void* GetData() override;
    size_t GetLength() override;
    size_t GetOffset() override;
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_TYPED_ARRAY_H */
