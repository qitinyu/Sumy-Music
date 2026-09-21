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

#include "quickjs_native_big_int.h"

QuickJSNativeBigInt::QuickJSNativeBigInt(QuickJSNativeEngine* engine, JSValue value) : QuickJSNativeValue(engine, value)
{}

QuickJSNativeBigInt::QuickJSNativeBigInt(QuickJSNativeEngine* engine, int64_t value)
    : QuickJSNativeBigInt(engine, JS_NewBigInt64(engine->GetContext(), value))
{}

QuickJSNativeBigInt::QuickJSNativeBigInt(QuickJSNativeEngine* engine, uint64_t value, bool isUnit64)
    : QuickJSNativeBigInt(engine, JS_NewBigUint64(engine->GetContext(), value))
{}

QuickJSNativeBigInt::~QuickJSNativeBigInt() {}

void* QuickJSNativeBigInt::GetInterface(int interfaceId)
{
    return (NativeBigint::INTERFACE_ID == interfaceId) ? (NativeBigint*)this : nullptr;
}

void QuickJSNativeBigInt::Uint64Value(uint64_t* cValue, bool* lossless)
{
    JS_ToUInt64WithBigInt(engine_->GetContext(), this->value_, cValue, lossless);
}
void QuickJSNativeBigInt::Int64Value(int64_t* cValue, bool* lossless)
{
    JS_ToInt64WithBigInt(engine_->GetContext(), this->value_, cValue, lossless);
}

bool QuickJSNativeBigInt::GetWordsArray(int* signBit, size_t* wordCount, uint64_t* words)
{
    return JS_GetBigIntWords(engine_->GetContext(), this->value_, signBit, wordCount, words);
}

QuickJSNativeBigInt::operator int64_t()
{
    int64_t cValue = 0;
    bool lossless = true;
    Int64Value(&cValue, &lossless);
    return cValue;
}

QuickJSNativeBigInt::operator uint64_t()
{
    uint64_t cValue = 0;
    bool lossless = true;
    Uint64Value(&cValue, &lossless);
    return cValue;
}
