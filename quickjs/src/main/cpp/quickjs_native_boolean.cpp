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

#include "quickjs_native_boolean.h"

QuickJSNativeBoolean::QuickJSNativeBoolean(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeValue(engine, value)
{
}

QuickJSNativeBoolean::QuickJSNativeBoolean(QuickJSNativeEngine* engine, bool value)
    : QuickJSNativeBoolean(engine, value ? JS_TRUE : JS_FALSE)
{
}

QuickJSNativeBoolean::~QuickJSNativeBoolean() {}

void* QuickJSNativeBoolean::GetInterface(int interfaceId)
{
    return (interfaceId == NativeBoolean::INTERFACE_ID) ? (NativeBoolean*)this : nullptr;
}

QuickJSNativeBoolean::operator bool()
{
    return JS_VALUE_GET_BOOL((JSValue)value_);
}
