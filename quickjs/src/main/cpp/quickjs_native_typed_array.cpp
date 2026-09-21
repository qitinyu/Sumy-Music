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

#include "quickjs_native_typed_array.h"
#include <string.h>

QuickJSNativeTypedArray::QuickJSNativeTypedArray(QuickJSNativeEngine* engine, JSValue value) : QuickJSNativeObject(engine, value)
{
    
}

QuickJSNativeTypedArray::QuickJSNativeTypedArray(QuickJSNativeEngine* engine, NativeTypedArrayType type, NativeValue* value, size_t length, size_t offset) : QuickJSNativeTypedArray(engine, JS_NULL)
{
    JSValue jsGlobal = JS_GetGlobalObject(engine_->GetContext());
    JSValue jsType;
    switch (type) {
        case NativeTypedArrayType::NATIVE_UINT8_CLAMPED_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Uint8ClampedArray");
            break;
        case NativeTypedArrayType::NATIVE_INT8_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Int8Array");
            break;
        case NativeTypedArrayType::NATIVE_UINT8_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Uint8Array");
            break;
        case NativeTypedArrayType::NATIVE_INT16_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Int16Array");
            length = length / sizeof(int16_t);
            break;
        case NativeTypedArrayType::NATIVE_UINT16_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Uint16Array");
            length = length / sizeof(uint16_t);
            break;
        case NativeTypedArrayType::NATIVE_INT32_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Int32Array");
            length = length / sizeof(int32_t);
            break;
        case NativeTypedArrayType::NATIVE_UINT32_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Uint32Array");
            length = length / sizeof(uint32_t);
            break;
        case NativeTypedArrayType::NATIVE_BIGINT64_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "BigInt64Array");
            break;
        case NativeTypedArrayType::NATIVE_BIGUINT64_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "BigUint64Array");
            break;
        case NativeTypedArrayType::NATIVE_FLOAT32_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Float32Array");
            length = length / sizeof(float);
            break;
        case NativeTypedArrayType::NATIVE_FLOAT64_ARRAY:
            jsType = JS_GetPropertyStr(engine_->GetContext(), jsGlobal, "Float64Array");
            length = length / sizeof(double);
            break;
        default:;
    }
    JSValue params[] = {
        *value,
        JS_NewInt64(engine_->GetContext(), offset),
        JS_NewInt64(engine_->GetContext(), length),
    };
    value_ = JS_CallConstructor(engine_->GetContext(), jsType, 3, params);
    JS_FreeValue(engine_->GetContext(), jsType);
    JS_FreeValue(engine_->GetContext(), jsGlobal);
}

QuickJSNativeTypedArray::~QuickJSNativeTypedArray() {
    
}

void* QuickJSNativeTypedArray::GetInterface(int interfaceId)
{
    return (NativeTypedArray::INTERFACE_ID == interfaceId) ? (NativeTypedArray*)this : QuickJSNativeObject::GetInterface(interfaceId);
}

NativeTypedArrayType QuickJSNativeTypedArray::GetTypedArrayType()
{
    JSValue constructor = JS_GetPropertyStr(engine_->GetContext(), value_, "constructor");
    JSValue constructorName = JS_GetPropertyStr(engine_->GetContext(), constructor, "name");
    const char* cConstructorName = JS_ToCString(engine_->GetContext(), constructorName);

    NativeTypedArrayType typedArrayType;

    if (!strcmp(cConstructorName, "Uint8ClampedArray")) {
        typedArrayType = NativeTypedArrayType::NATIVE_UINT8_CLAMPED_ARRAY;
    } else if (!strcmp(cConstructorName, "Int8Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_INT8_ARRAY;
    } else if (!strcmp(cConstructorName, "Uint8Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_UINT8_ARRAY;
    } else if (!strcmp(cConstructorName, "Int16Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_INT16_ARRAY;
    } else if (!strcmp(cConstructorName, "Uint16Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_UINT16_ARRAY;
    } else if (!strcmp(cConstructorName, "Int32Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_INT32_ARRAY;
    } else if (!strcmp(cConstructorName, "Uint32Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_UINT32_ARRAY;
    } else if (!strcmp(cConstructorName, "BigInt64Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_BIGINT64_ARRAY;
    } else if (!strcmp(cConstructorName, "BigUint64Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_BIGUINT64_ARRAY;
    } else if (!strcmp(cConstructorName, "Float32Array")) {
        typedArrayType = NativeTypedArrayType::NATIVE_FLOAT32_ARRAY;
    } else {
        typedArrayType = NativeTypedArrayType::NATIVE_FLOAT64_ARRAY;
    }

    JS_FreeCString(engine_->GetContext(), cConstructorName);
    JS_FreeValue(engine_->GetContext(), constructorName);
    JS_FreeValue(engine_->GetContext(), constructor);

    return typedArrayType;
}

size_t QuickJSNativeTypedArray::GetLength()
{
    JSValue byteLength = JS_GetPropertyStr(engine_->GetContext(), value_, "byteLength");
    size_t result = JS_VALUE_GET_INT(byteLength);
    JS_FreeValue(engine_->GetContext(), byteLength);
    
    return result;
}

NativeValue* QuickJSNativeTypedArray::GetArrayBuffer()
{
    JSValue arrayBuffer = JS_GetPropertyStr(engine_->GetContext(), value_, "buffer");
    
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, arrayBuffer);
}

void* QuickJSNativeTypedArray::GetData()
{
    void* buffer = nullptr;
    size_t bufferSize;
    JSValue arrayBuffer = JS_GetPropertyStr(engine_->GetContext(), value_, "buffer");
    buffer = JS_GetArrayBuffer(engine_->GetContext(), &bufferSize, arrayBuffer);
    JS_FreeValue(engine_->GetContext(), arrayBuffer);
    
    return buffer;
}

size_t QuickJSNativeTypedArray::GetOffset()
{
    JSValue byteOffset = JS_GetPropertyStr(engine_->GetContext(), value_, "byteOffset");
    uint32_t cValue = 0;
    JS_ToUint32(engine_->GetContext(), &cValue, byteOffset);
    JS_FreeValue(engine_->GetContext(), byteOffset);
    
    return cValue;
}
