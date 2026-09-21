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

#include "quickjs_native_array.h"
#include "native_engine/native_engine.h"
#include "quickjs_headers.h"

QuickJSNativeArray::QuickJSNativeArray(QuickJSNativeEngine* engine, JSValue value) : QuickJSNativeObject(engine, value)
{
}

QuickJSNativeArray::QuickJSNativeArray(QuickJSNativeEngine* engine, uint32_t length)
    : QuickJSNativeArray(engine, JS_NULL)
{
    value_ = JS_NewArray(engine_->GetContext());
    JSValue jsLength = JS_NewInt32(engine_->GetContext(), length);
    if (length != 0) {
        JS_SetPropertyStr(engine_->GetContext(), value_, "length", jsLength);
    }
    JS_FreeValue(engine_->GetContext(), jsLength);
}

QuickJSNativeArray::~QuickJSNativeArray() {}

void* QuickJSNativeArray::GetInterface(int interfaceId)
{
    return (NativeArray::INTERFACE_ID == interfaceId) ? (NativeArray*)this
                                                      : QuickJSNativeObject::GetInterface(interfaceId);
}

bool QuickJSNativeArray::SetElement(uint32_t index, NativeValue* value)
{
    return JS_SetPropertyUint32(engine_->GetContext(), value_, index, JS_DupValue(engine_->GetContext(), *value));
}

NativeValue* QuickJSNativeArray::GetElement(uint32_t index)
{
    JSValue value = JS_UNDEFINED;
    value = JS_GetPropertyUint32(engine_->GetContext(), value_, index);
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, value);
}

bool QuickJSNativeArray::HasElement(uint32_t index)
{
    bool result = false;
    JSAtom key = JS_NewAtomUInt32(engine_->GetContext(), index);
    result = JS_HasProperty(engine_->GetContext(), value_, key);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

bool QuickJSNativeArray::DeleteElement(uint32_t index)
{
    bool result = false;
    JSAtom spliceKey = JS_NewAtom(engine_->GetContext(), "splice");
    JSValue params[] = { JS_NewInt32(engine_->GetContext(), index), JS_NewInt32(engine_->GetContext(), 0) };
    JSValue spliceResult = JS_Invoke(engine_->GetContext(), value_, spliceKey, 2, params);

    if (!JS_IsNull(spliceResult) && !JS_IsUndefined(spliceResult)) {
        JS_FreeValue(engine_->GetContext(), value_);
        value_ = spliceResult;
        result = true;
    }
    JS_FreeAtom(engine_->GetContext(), spliceKey);
    return result;
}

uint32_t QuickJSNativeArray::GetLength()
{
    JSValue jsLength = JS_GetPropertyStr(engine_->GetContext(), value_, "length");
    uint32_t cLength = 0;
    JS_ToUint32(engine_->GetContext(), &cLength, jsLength);
    JS_FreeValue(engine_->GetContext(), jsLength);

    return cLength;
}
