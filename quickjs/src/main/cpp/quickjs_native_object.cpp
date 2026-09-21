/*
 * Copyright (c) 2021-2022 Huawei Device Co., Ltd.
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

#include "quickjs_native_object.h"
#include "native_engine/native_engine.h"
#include "native_engine/native_property.h"
#include "quickjs_headers.h"
#include "quickjs_native_array.h"
#include "quickjs_native_big_int.h"
#include "quickjs_native_engine.h"
#include "quickjs_native_function.h"
#include "quickjs_native_string.h"
#include "utils/log.h"

QuickJSNativeObject::QuickJSNativeObject(QuickJSNativeEngine* engine)
    : QuickJSNativeObject(engine, JS_NewObject(engine->GetContext()))
{
}

QuickJSNativeObject::QuickJSNativeObject(QuickJSNativeEngine* engine, JSValue value) : QuickJSNativeValue(engine, value)
{
}

QuickJSNativeObject::~QuickJSNativeObject() {}

void QuickJSNativeObject::SetNativePointer(void* pointer, NativeFinalize cb, void* hint)
{
    NativeObjectInfo* info = (NativeObjectInfo*)JS_GetNativePointer(engine_->GetContext(), value_);
    if (info == nullptr) {
        info = new NativeObjectInfo();
        if (info != nullptr) {
            info->callback = cb;
            info->engine = engine_;
            info->nativeObject = pointer;
            info->hint = hint;
        }
        JS_SetNativePointer(
            engine_->GetContext(), value_, info,
            [](JSContext* context, void* data, void* hint) {
                auto info = reinterpret_cast<NativeObjectInfo*>(data);
                if (info) {
                    info->callback(info->engine, info->nativeObject, info->hint);
                    delete info;
                }
            },
            hint);
    } else if (pointer == nullptr) {
        JS_SetNativePointer(engine_->GetContext(), value_, nullptr, nullptr, nullptr);
        delete info;
    }
}

void* QuickJSNativeObject::GetNativePointer()
{
    NativeObjectInfo* info = (NativeObjectInfo*)JS_GetNativePointer(engine_->GetContext(), value_);
    return info ? info->nativeObject : nullptr;
}

void QuickJSNativeObject::AddFinalizer(void* pointer, NativeFinalize cb, void* hint)
{
    NativeObjectInfo* info = (NativeObjectInfo*)JS_GetNativePointer(engine_->GetContext(), value_);
    if (info == nullptr) {
        info = new NativeObjectInfo();
        if (info != nullptr) {
            info->callback = cb;
            info->engine = engine_;
            info->nativeObject = pointer;
            info->hint = hint;
        }
    }
    if (info == nullptr) {
        return;
    }

    JS_AddFinalizer(
        engine_->GetContext(), value_, info,
        [](JSContext* context, void* data, void* hint) {
            auto info = reinterpret_cast<NativeObjectInfo*>(data);
            if (info) {
                info->callback(info->engine, info->nativeObject, info->hint);
                delete info;
            }
        },
        hint);
}

void* QuickJSNativeObject::GetInterface(int interfaceId)
{
    return (NativeObject::INTERFACE_ID == interfaceId) ? (NativeObject*)this : nullptr;
}

NativeValue* QuickJSNativeObject::GetPropertyNames()
{
    JSPropertyEnum* tab = nullptr;
    uint32_t len = 0;

    JS_GetOwnPropertyNames(engine_->GetContext(), &tab, &len, value_, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY);

    QuickJSNativeArray* propertyNames = new QuickJSNativeArray(engine_, (uint32_t)0);
    if (propertyNames == nullptr) {
        HILOG_ERROR("create property names failed");
        return nullptr;
    }

    for (uint32_t i = 0; i < len; i++) {
        QuickJSNativeString* name = new QuickJSNativeString(engine_, tab[i].atom);
        propertyNames->SetElement(i, name);
    }

    return propertyNames;
}

NativeValue* QuickJSNativeObject::GetPrototype()
{
    JSValue value = JS_GetPrototype(engine_->GetContext(), value_);
    return new QuickJSNativeObject(engine_, value);
}

bool QuickJSNativeObject::DefineProperty(NativePropertyDescriptor propertyDescriptor)
{
    JSAtom jKey = JS_NewAtom(engine_->GetContext(), propertyDescriptor.utf8name);

    bool result = false;

    if (propertyDescriptor.value) {
        result = JS_DefinePropertyValue(engine_->GetContext(), value_, jKey,
            JS_DupValue(engine_->GetContext(), *propertyDescriptor.value), JS_PROP_C_W_E);
    } else if (propertyDescriptor.method) {
        NativeValue* function = new QuickJSNativeFunction(engine_, propertyDescriptor.utf8name,
                                                          propertyDescriptor.method, propertyDescriptor.data);
        if (function != nullptr) {
            result = JS_DefinePropertyValue(engine_->GetContext(), value_, jKey,
                                            JS_DupValue(engine_->GetContext(), *function),
                                            JS_PROP_CONFIGURABLE | JS_PROP_WRITABLE);
        }
    } else if (propertyDescriptor.getter || propertyDescriptor.setter) {
        NativeValue* getter =
            new QuickJSNativeFunction(engine_, nullptr, propertyDescriptor.getter, propertyDescriptor.data);
        NativeValue* setter =
            new QuickJSNativeFunction(engine_, nullptr, propertyDescriptor.setter, propertyDescriptor.data);
        if (getter != nullptr && setter != nullptr) {
            result = JS_DefinePropertyGetSet(engine_->GetContext(), value_, jKey,
                                             JS_DupValue(engine_->GetContext(), *getter),
                                             JS_DupValue(engine_->GetContext(), *setter),
                                             JS_PROP_C_W_E);
        }
    }

    JS_FreeAtom(engine_->GetContext(), jKey);

    return result;
}

bool QuickJSNativeObject::SetProperty(NativeValue* key, NativeValue* value)
{
    bool result = false;
    JSAtom jKey = JS_ValueToAtom(engine_->GetContext(), *key);
    result = JS_SetProperty(engine_->GetContext(), value_, jKey, JS_DupValue(engine_->GetContext(), *value));
    JS_FreeAtom(engine_->GetContext(), jKey);

    return result;
}

NativeValue* QuickJSNativeObject::GetProperty(NativeValue* key)
{
    JSValue value = JS_UNDEFINED;
    JSAtom atomKey = JS_ValueToAtom(engine_->GetContext(), *key);
    value = JS_GetProperty(engine_->GetContext(), value_, atomKey);
    JS_FreeAtom(engine_->GetContext(), atomKey);
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, value);
}

bool QuickJSNativeObject::HasProperty(NativeValue* key)
{
    bool result = false;
    JSAtom jKey = JS_ValueToAtom(engine_->GetContext(), *key);
    result = JS_HasProperty(engine_->GetContext(), value_, jKey);
    JS_FreeAtom(engine_->GetContext(), jKey);
    return result;
}

bool QuickJSNativeObject::DeleteProperty(NativeValue* key)
{
    bool result = false;
    JSAtom jKey = JS_ValueToAtom(engine_->GetContext(), *key);
    result = JS_DeleteProperty(engine_->GetContext(), value_, jKey, JS_PROP_THROW);
    JS_FreeAtom(engine_->GetContext(), jKey);
    return result;
}

bool QuickJSNativeObject::SetProperty(const char* name, NativeValue* value)
{
    return JS_SetPropertyStr(engine_->GetContext(), value_, name, JS_DupValue(engine_->GetContext(), *value));
}

NativeValue* QuickJSNativeObject::GetProperty(const char* name)
{
    JSValue value = JS_UNDEFINED;
    value = JS_GetPropertyStr(engine_->GetContext(), value_, name);
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, value);
}

bool QuickJSNativeObject::HasProperty(const char* name)
{
    bool result = false;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_HasProperty(engine_->GetContext(), value_, key);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

bool QuickJSNativeObject::DeleteProperty(const char* name)
{
    bool result = false;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_DeleteProperty(engine_->GetContext(), value_, key, JS_PROP_THROW);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

bool QuickJSNativeObject::SetPrivateProperty(const char* name, NativeValue* value)
{
    bool result = false;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_SetPropertyInternal(engine_->GetContext(), value_, key, JS_DupValue(engine_->GetContext(), *value),
                                    JS_PROP_C_W_E | JS_PROP_THROW);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

NativeValue* QuickJSNativeObject::GetPrivateProperty(const char* name)
{
    JSValue result = JS_UNDEFINED;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_GetPropertyInternal(engine_->GetContext(), value_, key, value_, false);
    JS_FreeAtom(engine_->GetContext(), key);
    return QuickJSNativeEngine::JSValueToNativeValue(engine_, result);
}

bool QuickJSNativeObject::HasPrivateProperty(const char* name)
{
    bool result = false;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_HasProperty(engine_->GetContext(), value_, key);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

bool QuickJSNativeObject::DeletePrivateProperty(const char* name)
{
    bool result = false;
    JSAtom key = JS_NewAtom(engine_->GetContext(), name);
    result = JS_DeleteProperty(engine_->GetContext(), value_, key, JS_PROP_C_W_E | JS_PROP_THROW);
    JS_FreeAtom(engine_->GetContext(), key);
    return result;
}

NativeValue* QuickJSNativeObject::GetAllPropertyNames(
    napi_key_collection_mode keyMode, napi_key_filter keyFilter, napi_key_conversion keyConversion)
{
    auto getPower = JS_PROP_CONFIGURABLE;
    if (keyFilter == napi_key_all_properties) {
        getPower = getPower | JS_PROP_GETSET | JS_PROP_WRITABLE | JS_PROP_ENUMERABLE | JS_PROP_CONFIGURABLE;
    } else {
        if (keyFilter == napi_key_writable) {
            getPower = getPower | JS_PROP_WRITABLE | JS_PROP_GETSET;
        }

        if (keyFilter == napi_key_enumerable) {
            getPower = getPower | JS_PROP_ENUMERABLE;
        }

        if (keyFilter == napi_key_configurable) {
            getPower = getPower | JS_PROP_CONFIGURABLE;
        }
    }

    JSPropertyEnum* tab = nullptr;
    uint32_t len = 0;

    JS_GetOwnPropertyNames(engine_->GetContext(), &tab, &len, value_, getPower);

    QuickJSNativeArray* propertyNames = new QuickJSNativeArray(engine_, len);
    if (propertyNames == nullptr) {
        HILOG_ERROR("create property names failed");
        return nullptr;
    }

    for (uint32_t i = 0; i < len; i++) {
        QuickJSNativeString* name = new QuickJSNativeString(engine_, tab[i].atom);
        propertyNames->SetElement(i, name);
    }

    return propertyNames;
}

bool QuickJSNativeObject::AssociateTypeTag(NapiTypeTag* typeTag)
{
    constexpr uint32_t size = 2;
    const char name[] = "ACENAPI_TYPETAG";
    bool result = false;
    bool hasPribate = false;
    if (typeTag == nullptr) {
        return false;
    }
    uint64_t words[size] = {typeTag->lower, typeTag->upper};
    hasPribate = HasPrivateProperty(name);
    if (!hasPribate) {
        JSAtom key = JS_NewAtom(engine_->GetContext(), name);
        JSValue value = JS_CreateBigIntWords(engine_->GetContext(), 0, size, words);
        result = JS_SetPropertyInternal(engine_->GetContext(), value_, key,
            JS_DupValue(engine_->GetContext(), value), JS_PROP_C_W_E | JS_PROP_THROW);
        JS_FreeAtom(engine_->GetContext(), key);
    }
    return result;
}

bool QuickJSNativeObject::CheckTypeTag(NapiTypeTag* typeTag)
{
    constexpr uint32_t size = 2;
    const char name[] = "ACENAPI_TYPETAG";
    bool result = false;
    bool ret = false;
    if (typeTag == nullptr) {
        return ret;
    }
    result = HasPrivateProperty(name);
    if (result) {
        JSAtom key = JS_NewAtom(engine_->GetContext(), name);
        JSValue value = JS_GetPropertyInternal(engine_->GetContext(), value_, key, value_, false);
        JS_FreeAtom(engine_->GetContext(), key);

        int sign = 0;
        size_t wordCount = size;
        uint64_t words[size] = {0};
        result = JS_GetBigIntWords(engine_->GetContext(), value, &sign, &wordCount, words);
        if (result && wordCount >= size) {
            if ((words[0] == typeTag->lower) && (words[1] == typeTag->upper)) {
                ret = true;
            }
        }
    }
    return ret;
}

void QuickJSNativeObject::Freeze()
{
    JS_Freeze(engine_->GetContext(), value_);
}

void QuickJSNativeObject::Seal()
{
    JS_Seal(engine_->GetContext(), value_);
}