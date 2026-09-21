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

#include "quickjs_native_data_view.h"
#include "native_engine/native_engine.h"
#include "quickjs_headers.h"
#include "quickjs_native_array_buffer.h"

QuickJSNativeDataView::QuickJSNativeDataView(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeObject(engine, value)
{
}

QuickJSNativeDataView::QuickJSNativeDataView(QuickJSNativeEngine* engine,
                                             NativeValue* value,
                                             size_t length,
                                             size_t offset)
    : QuickJSNativeDataView(engine, JS_NULL)
{
    JSValue global = JS_GetGlobalObject(engine_->GetContext());
    JSValue dataView = JS_GetPropertyStr(engine_->GetContext(), global, "DataView");

    JSValue param[] = {
        *value,
        JS_NewInt64(engine_->GetContext(), offset),
        JS_NewInt64(engine_->GetContext(), length),
    };

    value_ = JS_CallConstructor(engine_->GetContext(), dataView, 3, param);

    JS_FreeValue(engine_->GetContext(), dataView);
    JS_FreeValue(engine_->GetContext(), global);
}

QuickJSNativeDataView::~QuickJSNativeDataView() {}

void* QuickJSNativeDataView::GetInterface(int interfaceId)
{
    return (NativeDataView::INTERFACE_ID == interfaceId) ? (NativeDataView*)this
                                                         : QuickJSNativeObject::GetInterface(interfaceId);
}

void* QuickJSNativeDataView::GetBuffer()
{
    void* buffer = nullptr;
    size_t bufferSize = 0;
    JSValue arrayBuffer = JS_GetPropertyStr(engine_->GetContext(), value_, "buffer");
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, arrayBuffer);
    JS_FreeValue(engine_->GetContext(), arrayBuffer);
    return buffer;
}

size_t QuickJSNativeDataView::GetLength()
{
    uint32_t length = 0;
    JSValue byteLength = JS_GetPropertyStr(engine_->GetContext(), value_, "byteLength");
    JS_ToUint32(engine_->GetContext(), &length, byteLength);
    JS_FreeValue(engine_->GetContext(), byteLength);
    return length;
}

NativeValue* QuickJSNativeDataView::GetArrayBuffer()
{
    JSValue buffer = JS_GetPropertyStr(engine_->GetContext(), value_, "buffer");
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, buffer);
}

size_t QuickJSNativeDataView::GetOffset()
{
    JSValue byteOffset = JS_GetPropertyStr(engine_->GetContext(), value_, "byteOffset");
    uint32_t cValue = 0;
    JS_ToUint32(engine_->GetContext(), &cValue, byteOffset);
    JS_FreeValue(engine_->GetContext(), byteOffset);
    return cValue;
}
