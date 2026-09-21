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

#include "quickjs_native_value.h"
#include "quickjs_native_boolean.h"
#include "quickjs_native_number.h"
#include "quickjs_native_object.h"
#include "quickjs_native_string.h"

QuickJSNativeValue::QuickJSNativeValue(QuickJSNativeEngine* engine, JSValue value)
{
    value_ = value;
    engine_ = engine;
//     NativeScopeManager* scopeManager = engine_->GetScopeManager();
//     if (scopeManager != nullptr) {
//         scopeManager->CreateHandle(this);
//     }
}

QuickJSNativeValue::~QuickJSNativeValue()
{
    JS_FreeValue(engine_->GetContext(), value_);
}

void* QuickJSNativeValue::GetInterface(int interfaceId)
{
    return nullptr;
}

NativeValueType QuickJSNativeValue::TypeOf()
{
    NativeValueType result;
    switch (JS_VALUE_GET_NORM_TAG((JSValue)value_)) {
        case JS_TAG_BIG_INT:
        case JS_TAG_BIG_FLOAT:
            result = NativeValueType::NATIVE_BIGINT;
            break;
        case JS_TAG_SYMBOL:
            result = NativeValueType::NATIVE_SYMBOL;
            break;
        case JS_TAG_STRING:
            result = NativeValueType::NATIVE_STRING;
            break;
        case JS_TAG_OBJECT:
            if (JS_IsFunction(engine_->GetContext(), value_)) {
                result = NativeValueType::NATIVE_FUNCTION;
            } else if (JS_IsExternal(engine_->GetContext(), value_)) {
                result = NativeValueType::NATIVE_EXTERNAL;
            } else {
                result = NativeValueType::NATIVE_OBJECT;
            }
            break;
        case JS_TAG_INT:
        case JS_TAG_FLOAT64:
            result = NativeValueType::NATIVE_NUMBER;
            break;
        case JS_TAG_BOOL:
            result = NativeValueType::NATIVE_BOOLEAN;
            break;
        case JS_TAG_NULL:
            result = NativeValueType::NATIVE_NULL;
            break;
        default:
            result = NativeValueType::NATIVE_UNDEFINED;
    }
    return result;
}

bool QuickJSNativeValue::InstanceOf(NativeValue* obj)
{
    return JS_IsInstanceOf(engine_->GetContext(), value_, *obj);
}

bool QuickJSNativeValue::IsArray()
{
    return JS_IsArray(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsArrayBuffer()
{
    return JS_IsArrayBuffer(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsBuffer()
{
    return JS_IsBuffer(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsDate()
{
    return JS_IsDate(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsError()
{
    return JS_IsError(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsTypedArray()
{
    return JS_IsTypedArray(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsDataView()
{
    return JS_IsDataView(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsPromise()
{
    return JS_IsPromise(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsCallable()
{
    return JS_IsFunction(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsMapIterator()
{
    return JS_IsMapIterator(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsSetIterator()
{
    return JS_IsSetIterator(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsGeneratorObject()
{
    return JS_IsGeneratorObject(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsModuleNamespaceObject()
{
    return JS_IsModuleNamespaceObject(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsProxy()
{
    return JS_IsProxy(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsRegExp()
{
    return JS_IsRegExp(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsNumberObject()
{
    return JS_IsNumberObject(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsMap()
{
    return JS_IsMap(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsSet()
{
    return JS_IsSet(engine_->GetContext(), value_);
}

bool QuickJSNativeValue::IsArgumentsObject()
{
    return false;
}

bool QuickJSNativeValue::IsAsyncFunction()
{
    return false;
}

bool QuickJSNativeValue::IsBooleanObject()
{
    return false;
}

bool QuickJSNativeValue::IsGeneratorFunction()
{
    return false;
}

bool QuickJSNativeValue::IsStringObject()
{
    return false;
}

bool QuickJSNativeValue::IsSymbolObject()
{
    return false;
}

bool QuickJSNativeValue::IsWeakMap()
{
    return false;
}

bool QuickJSNativeValue::IsWeakSet()
{
    return false;
}

NativeValue* QuickJSNativeValue::ToBoolean()
{
    bool cValue = JS_ToBool(engine_->GetContext(), value_);
    return new QuickJSNativeBoolean(engine_, cValue);
}

NativeValue* QuickJSNativeValue::ToNumber()
{
    double cValue = 0;
    JS_ToFloat64(engine_->GetContext(), &cValue, value_);
    return new QuickJSNativeNumber(engine_, cValue);
}

NativeValue* QuickJSNativeValue::ToString()
{
    JSValue value = JS_ToString(engine_->GetContext(), value_);
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, value);
}

NativeValue* QuickJSNativeValue::ToObject()
{
    return nullptr;
}

bool QuickJSNativeValue::StrictEquals(NativeValue* value)
{
    return JS_StrictEquals(engine_->GetContext(), value_, *value);
}
