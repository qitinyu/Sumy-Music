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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_NATIVE_REFERENCE_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_NATIVE_REFERENCE_H

#include "native_value.h"

class NativeReference {
public:
    virtual ~NativeReference() {}
    virtual uint32_t Ref() = 0;
    virtual uint32_t Unref() = 0;
    virtual NativeValue* Get() = 0;
    virtual void* GetData()
    {
        return nullptr;
    }
    virtual operator NativeValue*() = 0;
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_NATIVE_REFERENCE_H */
