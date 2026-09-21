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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_REFERENCE_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_REFERENCE_H

#include "native_engine/native_reference.h"

#include "quickjs_native_engine.h"

class QuickJSNativeReference : public NativeReference {
public:
    QuickJSNativeReference(QuickJSNativeEngine* engine, NativeValue* value, uint32_t initialRefcount,
        NativeFinalize callback = nullptr, void* data = nullptr, void* hint = nullptr);
    ~QuickJSNativeReference() override;

    uint32_t Ref() override;
    uint32_t Unref() override;
    NativeValue* Get() override;
    operator NativeValue*() override;

private:
    QuickJSNativeEngine* engine_;
    JSValue value_;
    uint32_t refCount_;
    NativeFinalize callback_ = nullptr;
    void* data_ = nullptr;
    void* hint_ = nullptr;

    void FinalizeCallback(void);
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_REFERENCE_H */
