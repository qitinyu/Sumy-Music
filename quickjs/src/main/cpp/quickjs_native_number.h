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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_NUMBER_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_NUMBER_H

#include "quickjs_native_value.h"

class QuickJSNativeNumber : public QuickJSNativeValue, public NativeNumber {
public:
    QuickJSNativeNumber(QuickJSNativeEngine* engine, JSValue value);
    QuickJSNativeNumber(QuickJSNativeEngine* engine, int32_t value);
    QuickJSNativeNumber(QuickJSNativeEngine* engine, uint32_t value);
    QuickJSNativeNumber(QuickJSNativeEngine* engine, int64_t value);
    QuickJSNativeNumber(QuickJSNativeEngine* engine, double value);
    ~QuickJSNativeNumber() override;

    void* GetInterface(int interfaceId) override;

    operator int32_t() override;
    operator uint32_t() override;
    operator int64_t() override;
    operator double() override;
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_NATIVE_VALUE_QUICKJS_NATIVE_NUMBER_H */
