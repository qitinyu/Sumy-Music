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

#include "quickjs_native_function.h"
#include "native_engine/native_value.h"
#include "quickjs_native_engine.h"
#include "quickjs_native_number.h"
#include "quickjs_native_object.h"

#include "utils/log.h"

QuickJSNativeFunction::QuickJSNativeFunction(QuickJSNativeEngine* engine, JSValue value)
    : QuickJSNativeObject(engine, value)
{
}

QuickJSNativeFunction::QuickJSNativeFunction(QuickJSNativeEngine* engine,
                                             const char* name,
                                             NativeCallback cb,
                                             void* value)
    : QuickJSNativeObject(engine, JS_UNDEFINED)
{
    NativeFunctionInfo* info = NativeFunctionInfo::CreateNewInstance();
    if (info != nullptr) {
        info->engine = engine;
        info->callback = cb;
        info->data = value;
    }

    JSValue functionContext = JS_NewExternal(engine_->GetContext(), info,
                                             [](JSContext* ctx, void* data, void* hint) {
                                                 auto info = (NativeFunctionInfo*)data;
                                                 if (info != nullptr) {
                                                     delete info;
                                                 }
                                             },
                                             nullptr);

    value_ = JS_NewCFunctionData(engine_->GetContext(), JSCFunctionData, 0, 0, 1, &functionContext);
    JS_DefinePropertyValueStr(engine_->GetContext(), value_, "_functionContext", functionContext, 0);
}

QuickJSNativeFunction::~QuickJSNativeFunction() {}

void* QuickJSNativeFunction::GetInterface(int interfaceId)
{
    return (NativeFunction::INTERFACE_ID == interfaceId) ? (NativeFunction *)this
                                                         : QuickJSNativeObject::GetInterface(interfaceId);
}

JSValue QuickJSNativeFunction::JSCFunctionData(JSContext* ctx,
                                               JSValueConst thisVal,
                                               int argc,
                                               JSValueConst* argv,
                                               int magic,
                                               JSValue* funcData)
{
    auto info = (NativeFunctionInfo*)JS_ExternalToNativeObject(ctx, *funcData);
    if (info == nullptr) {
        HILOG_ERROR("info is null");
        return JS_UNDEFINED;
    }

    NativeValue* value = nullptr;
    NativeCallbackInfo callbackInfo = {0};

    QuickJSNativeEngine* engine = (QuickJSNativeEngine*)info->engine;
    if (engine == nullptr) {
        HILOG_ERROR("engine is null");
        return JS_UNDEFINED;
    }

    NativeScopeManager* scopeManager = engine->GetScopeManager();
    if (scopeManager == nullptr) {
        HILOG_ERROR("scope manager is null");
        return JS_UNDEFINED;
    }
    NativeScope* scope = scopeManager->OpenEscape();
    callbackInfo.thisVar = QuickJSNativeEngine::JSValueToNativeValue(engine, JS_DupValue(ctx, thisVal));

    callbackInfo.argc = argc;
    callbackInfo.argv = nullptr;
    callbackInfo.functionInfo = info;
    if (callbackInfo.argc > 0) {
        callbackInfo.argv = new NativeValue*[argc];
        for (int i = 0; i < argc && callbackInfo.argv != nullptr; i++) {
            callbackInfo.argv[i] = QuickJSNativeEngine::JSValueToNativeValue(engine, JS_DupValue(ctx, argv[i]));
        }
    }

    value = info->callback(info->engine, &callbackInfo);

    if (callbackInfo.argv != nullptr) {
        delete []callbackInfo.argv;
    }

    JSValue result = JS_UNDEFINED;
    if (value != nullptr) {
        result = JS_DupValue(ctx, *value);
    } else if (info->engine->IsExceptionPending()) {
        NativeValue* error = info->engine->GetAndClearLastException();
        if (error != nullptr) {
            result = JS_DupValue(ctx, *error);
        }
    }
    scopeManager->CloseEscape(scope);
    return result;
}
