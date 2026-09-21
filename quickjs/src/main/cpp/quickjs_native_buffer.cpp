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
#include "quickjs_native_buffer.h"

struct QuickJSBufferCallback {
    static QuickJSBufferCallback* CreateNewInstance()
    {
        return new QuickJSBufferCallback();
    }
    NativeEngine* engine = nullptr;
    NativeFinalize cb = nullptr;
    void* hint = nullptr;
};

QuickJSNativeBuffer::QuickJSNativeBuffer(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeObject(engine, value)
{
    SetPriviteProperty(engine_->GetContext(), value);
}

QuickJSNativeBuffer::QuickJSNativeBuffer(QuickJSNativeEngine* engine, uint8_t** value, size_t length)
    : QuickJSNativeBuffer(engine, JS_NULL)
{
    size_t size = 0;
    value_ = JS_NewArrayBufferCopy(engine_->GetContext(), nullptr, length);
    SetPriviteProperty(engine_->GetContext(), value_);
    *value = JS_GetArrayBuffer(engine_->GetContext(), &size, value_);
}

QuickJSNativeBuffer::QuickJSNativeBuffer(QuickJSNativeEngine* engine, uint8_t** value, size_t length, const void* data)
    : QuickJSNativeBuffer(engine, JS_NULL)
{
    size_t size = 0;
    if (data != nullptr) {
        value_ = JS_NewArrayBufferCopy(engine_->GetContext(), (uint8_t*)data, length);
        SetPriviteProperty(engine_->GetContext(), value_);
        *value = JS_GetArrayBuffer(engine_->GetContext(), &size, value_);
    }
}

QuickJSNativeBuffer::QuickJSNativeBuffer(
    QuickJSNativeEngine* engine, uint8_t* data, size_t length, NativeFinalize cb, void* hint)
    : QuickJSNativeObject(engine, JS_NULL)
{
    auto cbinfo = QuickJSBufferCallback::CreateNewInstance();
    if (cbinfo != nullptr) {
        cbinfo->engine = engine_;
        cbinfo->cb = cb;
        cbinfo->hint = hint;
    }
    value_ = JS_NewArrayBuffer(
        engine_->GetContext(), data, length,
        [](JSRuntime* rt, void* opaque, void* ptr) -> void {
            auto cbinfo = reinterpret_cast<QuickJSBufferCallback*>(opaque);
            if (cbinfo != nullptr && cbinfo->cb != nullptr) {
                cbinfo->cb(cbinfo->engine, ptr, cbinfo->hint);
                delete cbinfo;
            }
        },
        (void*)cbinfo, false);
    SetPriviteProperty(engine_->GetContext(), value_);
}

QuickJSNativeBuffer::~QuickJSNativeBuffer() {}

void* QuickJSNativeBuffer::GetInterface(int interfaceId)
{
    return (NativeBuffer::INTERFACE_ID == interfaceId) ? (NativeBuffer*)this
                                                       : QuickJSNativeObject::GetInterface(interfaceId);
}

void* QuickJSNativeBuffer::GetBuffer()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, value_);
    return buffer;
}

size_t QuickJSNativeBuffer::GetLength()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, value_);
    return bufferSize;
}

void QuickJSNativeBuffer::SetPriviteProperty(JSContext* context, JSValue value)
{
    JSAtom key = JS_NewAtom(context, "napi_buffer");
    JSValue keyValue = JS_NewBool(context, true);
    JS_SetPropertyInternal(context, value, key, JS_DupValue(context, keyValue), JS_PROP_C_W_E | JS_PROP_THROW);

    JS_FreeValue(engine_->GetContext(), keyValue);
    JS_FreeAtom(engine_->GetContext(), key);
}
