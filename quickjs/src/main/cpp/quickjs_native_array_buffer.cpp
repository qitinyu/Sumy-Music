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

#include "native_engine/native_engine.h"
#include "quickjs_native_array_buffer.h"

struct QuickJsArrayCallback {
    static QuickJsArrayCallback* CreateNewInstance() { return new QuickJsArrayCallback(); }
    NativeEngine* engine = nullptr;
    NativeFinalize cb = nullptr;
    void* hint = nullptr;
};

QuickJSNativeArrayBuffer::QuickJSNativeArrayBuffer(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeObject(engine, value)
{
}

QuickJSNativeArrayBuffer::QuickJSNativeArrayBuffer(QuickJSNativeEngine* engine, uint8_t** data, size_t length)
    : QuickJSNativeArrayBuffer(engine, JS_NULL)
{
    size_t size = 0;
    value_ = JS_NewArrayBufferCopy(engine_->GetContext(), nullptr, length);
    *data = JS_GetArrayBuffer(engine_->GetContext(), &size, value_);
}

QuickJSNativeArrayBuffer::QuickJSNativeArrayBuffer(QuickJSNativeEngine* engine,
                                                   uint8_t* data,
                                                   size_t length,
                                                   NativeFinalize cb,
                                                   void* hint)
    : QuickJSNativeObject(engine, JS_NULL)
{
    auto cbinfo = QuickJsArrayCallback::CreateNewInstance();
    if (cbinfo != nullptr) {
        cbinfo->engine = engine_;
        cbinfo->cb = cb;
        cbinfo->hint = hint;
    }
    value_ = JS_NewArrayBuffer(
        engine_->GetContext(), data, length,
        [](JSRuntime* rt, void* opaque, void* ptr) -> void {
            auto cbinfo = reinterpret_cast<QuickJsArrayCallback*>(opaque);
            if (cbinfo != nullptr) {
                cbinfo->cb(cbinfo->engine, ptr, cbinfo->hint);
                delete cbinfo;
            }
        },
        (void*)cbinfo, false);
}

QuickJSNativeArrayBuffer::~QuickJSNativeArrayBuffer() {}

void* QuickJSNativeArrayBuffer::GetInterface(int interfaceId)
{
    return (NativeArrayBuffer::INTERFACE_ID == interfaceId) ? (NativeArrayBuffer*)this
                                                            : QuickJSNativeObject::GetInterface(interfaceId);
}

void* QuickJSNativeArrayBuffer::GetBuffer()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, value_);
    return buffer;
}

size_t QuickJSNativeArrayBuffer::GetLength()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, value_);
    return bufferSize;
}

bool QuickJSNativeArrayBuffer::IsDetachedArrayBuffer()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, value_);
    return (buffer == nullptr);
}

bool QuickJSNativeArrayBuffer::DetachArrayBuffer()
{
    if (!IsDetachedArrayBuffer()) {
        JS_DetachArrayBuffer(engine_->GetContext(), value_);
        return true;
    } else {
        return false;
    }
}
