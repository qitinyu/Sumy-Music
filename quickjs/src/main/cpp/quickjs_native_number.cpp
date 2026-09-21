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

#include "quickjs_native_number.h"

QuickJSNativeNumber::QuickJSNativeNumber(QuickJSNativeEngine* engine, JSValue value) : QuickJSNativeValue(engine, value)
{
}

QuickJSNativeNumber::QuickJSNativeNumber(QuickJSNativeEngine* engine, int32_t value)
    : QuickJSNativeNumber(engine, JS_NewInt32(engine->GetContext(), value))
{
}

QuickJSNativeNumber::QuickJSNativeNumber(QuickJSNativeEngine* engine, uint32_t value)
    : QuickJSNativeNumber(engine, JS_NewInt32(engine->GetContext(), value))
{
}

QuickJSNativeNumber::QuickJSNativeNumber(QuickJSNativeEngine* engine, int64_t value)
    : QuickJSNativeNumber(engine, JS_NewInt64(engine->GetContext(), value))
{
}

QuickJSNativeNumber::QuickJSNativeNumber(QuickJSNativeEngine* engine, double value)
    : QuickJSNativeNumber(engine, JS_NewFloat64(engine->GetContext(), value))
{
}

QuickJSNativeNumber::~QuickJSNativeNumber() {}

void* QuickJSNativeNumber::GetInterface(int interfaceId)
{
    return (NativeNumber::INTERFACE_ID == interfaceId) ? (NativeNumber*)this : nullptr;
}

QuickJSNativeNumber::operator int32_t()
{
    int32_t cValue = 0;
    JS_ToInt32(engine_->GetContext(), &cValue, this->value_);
    return cValue;
}

QuickJSNativeNumber::operator uint32_t()
{
    uint32_t cValue = 0;
    JS_ToUint32(engine_->GetContext(), &cValue, this->value_);
    return cValue;
}

QuickJSNativeNumber::operator int64_t()
{
    int64_t cValue = 0;
    JS_ToInt64(engine_->GetContext(), &cValue, this->value_);
    return cValue;
}

QuickJSNativeNumber::operator double()
{
    double cValue = 0;
    JS_ToFloat64(engine_->GetContext(), &cValue, this->value_);
    return cValue;
}
