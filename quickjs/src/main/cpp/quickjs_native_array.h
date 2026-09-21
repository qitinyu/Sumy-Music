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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_ARRAY_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_ARRAY_H

#include "quickjs_native_object.h"

class QuickJSNativeArray : public QuickJSNativeObject, public NativeArray {
public:
    QuickJSNativeArray(QuickJSNativeEngine* engine, JSValue);
    QuickJSNativeArray(QuickJSNativeEngine* engine, uint32_t length);
    ~QuickJSNativeArray() override;

    bool SetElement(uint32_t index, NativeValue* value) override;
    NativeValue* GetElement(uint32_t index) override;
    bool HasElement(uint32_t index) override;
    bool DeleteElement(uint32_t index) override;

    void* GetInterface(int interfaceId) override;

    uint32_t GetLength() override;
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_ARRAY_H */
