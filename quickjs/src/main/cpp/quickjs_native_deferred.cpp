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

#include "quickjs_native_deferred.h"

QuickJSNativeDeferred::QuickJSNativeDeferred(QuickJSNativeEngine* engine, JSValue values[2])
    : engine_(engine), resolve_(values[0]), reject_(values[1])
{
}

QuickJSNativeDeferred::~QuickJSNativeDeferred()
{
    JS_FreeValue(engine_->GetContext(), resolve_);
    JS_FreeValue(engine_->GetContext(), reject_);
}

void QuickJSNativeDeferred::Resolve(NativeValue* data)
{
    JSValue value = JS_UNDEFINED;
    if (data != nullptr) {
        value = *data;
    }

    JSValue jsResult = JS_Call(engine_->GetContext(), resolve_, JS_UNDEFINED, 1, &value);
    JS_FreeValue(engine_->GetContext(), jsResult);
    js_std_loop(engine_->GetContext());
}

void QuickJSNativeDeferred::Reject(NativeValue* reason)
{
    JSValue value = JS_UNDEFINED;
    if (reason != nullptr) {
        value = *reason;
    }

    JSValue jsResult = JS_Call(engine_->GetContext(), reject_, JS_UNDEFINED, 1, &value);
    JS_FreeValue(engine_->GetContext(), jsResult);
    js_std_loop(engine_->GetContext());
}
