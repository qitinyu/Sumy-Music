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

#include "quickjs_native_external.h"

QuickJSNativeExternal::QuickJSNativeExternal(QuickJSNativeEngine* engine,
                                             void* value,
                                             NativeFinalize callback,
                                             void* hint)
    : QuickJSNativeValue(engine, JS_UNDEFINED)
{
    NativeObjectInfo* info = NativeObjectInfo::CreateNewInstance();
    if (info != nullptr) {
        info->engine = engine;
        info->nativeObject = value;
        info->callback = callback;
        info->hint = hint;
    }

    value_ = JS_NewExternal(
        engine->GetContext(), info,
        [](JSContext* context, void* data, void* hint) {
            auto info = reinterpret_cast<NativeObjectInfo*>(data);
            if (info != nullptr) {
                info->callback(info->engine, info->nativeObject, info->hint);
                delete info;
            }
        },
        nullptr);
}

QuickJSNativeExternal::QuickJSNativeExternal(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeValue(engine, value)
{
}

QuickJSNativeExternal::~QuickJSNativeExternal() {}

void* QuickJSNativeExternal::GetInterface(int interfaceId)
{
    return (NativeExternal::INTERFACE_ID == interfaceId) ? (NativeExternal*)this : nullptr;
}

QuickJSNativeExternal::operator void*()
{
    NativeObjectInfo* info = (NativeObjectInfo*)JS_ExternalToNativeObject(engine_->GetContext(), value_);
    return (info != nullptr) ? info->nativeObject : nullptr;
}