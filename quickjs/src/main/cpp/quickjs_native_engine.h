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

#ifndef FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_ENGINE_H
#define FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_ENGINE_H

#include "native_engine/native_engine.h"
#include "quickjs_headers.h"

class SerializeData {
public:
    SerializeData(size_t size, uint8_t* data) : dataSize_(size), value_(data) {}
    ~SerializeData() = default;

    uint8_t* GetData() const
    {
        return value_.get();
    }
    size_t GetSize() const
    {
        return dataSize_;
    }

private:
    struct Deleter {
        void operator()(uint8_t* ptr) const
        {
            free(ptr);
        }
    };

    size_t dataSize_;
    std::unique_ptr<uint8_t, Deleter> value_;
};

class QuickJSNativeEngine : public NativeEngine {
public:
    QuickJSNativeEngine(JSRuntime* runtime, JSContext* contex, void* jsEngine);
    ~QuickJSNativeEngine() override;

    JSRuntime* GetRuntime();
    JSContext* GetContext();

    void Loop(LoopMode mode, bool needSync = false) override;

    NativeValue* GetGlobal() override;
    NativeValue* CreateNull() override;
    NativeValue* CreateUndefined() override;
    NativeValue* CreateBoolean(bool value) override;
    NativeValue* CreateNumber(int32_t value) override;
    NativeValue* CreateNumber(uint32_t value) override;
    NativeValue* CreateNumber(int64_t value) override;
    NativeValue* CreateNumber(double value) override;
    NativeValue* CreateBigInt(int64_t value) override;
    NativeValue* CreateBigInt(uint64_t value) override;
    NativeValue* CreateString(const char* value, size_t length) override;
    NativeValue* CreateString16(const char16_t* value, size_t length) override;
    NativeValue* CreateSymbol(NativeValue* value) override;
    NativeValue* CreateExternal(void* value, NativeFinalize callback, void* hint) override;

    NativeValue* CreateObject() override;
    NativeValue* CreateFunction(const char* name, size_t length, NativeCallback cb, void* value) override;
    NativeValue* CreateArray(size_t length) override;

    NativeValue* CreateArrayBuffer(void** value, size_t length) override;
    NativeValue* CreateArrayBufferExternal(void* value, size_t length, NativeFinalize cb, void* hint) override;
    NativeValue* CreateBuffer(void** value, size_t length) override;
    NativeValue* CreateBufferCopy(void** value, size_t length, const void* data) override;
    NativeValue* CreateBufferExternal(void* value, size_t length, NativeFinalize cb, void* hint) override;
    NativeValue* CreateTypedArray(NativeTypedArrayType type, NativeValue* value, size_t length, size_t offset) override;
    NativeValue* CreateDataView(NativeValue* value, size_t length, size_t offset) override;
    NativeValue* CreatePromise(NativeDeferred** deferred) override;
    void SetPromiseRejectCallback(NativeReference* rejectCallbackRef, NativeReference* checkCallbackRef) override;

    NativeValue* CreateError(NativeValue* code, NativeValue* Message) override;
    NativeValue* CreateInstance(NativeValue* constructor, NativeValue* const* argv, size_t argc) override;

    NativeReference* CreateReference(NativeValue* value, uint32_t initialRefcount, NativeFinalize callback = nullptr, void* data = nullptr, void* hint = nullptr) override;
    NativeValue* CallFunction(NativeValue* thisVar, NativeValue* function, NativeValue* const* argv, size_t argc) override;

    NativeValue* DefineClass(const char* name, NativeCallback callback, void* data, const NativePropertyDescriptor* properties, size_t length) override;

    NativeValue* RunScript(NativeValue* script) override;
    NativeValue* RunBufferScript(std::vector<uint8_t>& buffer) override;
    NativeValue* RunActor(std::vector<uint8_t>& buffer, const char *descriptor) override;

    void SetPackagePath(const std::string& packagePath);

    bool Throw(NativeValue* error) override;
    bool Throw(NativeErrorType type, const char* code, const char* message) override;

    void* CreateRuntime() override;
    bool CheckTransferList(JSValue transferList);
    bool DetachTransferList(JSValue transferList);
    NativeValue* Serialize(NativeEngine* context, NativeValue* value, NativeValue* transfer) override;
    NativeValue* Deserialize(NativeEngine* context, NativeValue* recorder) override;
    void DeleteSerializationData(NativeValue* value) const override;
    ExceptionInfo* GetExceptionForWorker() const override;
    NativeValue* LoadModule(NativeValue* str, const std::string& fileName) override;

    static NativeValue* JSValueToNativeValue(QuickJSNativeEngine* engine, JSValue value);
    NativeValue* ValueToNativeValue(JSValueWrapper& value) override;
    JSValue GetModuleFromName(const std::string& moduleName, bool isAppModule, const std::string& id, const std::string& param, const std::string& instanceName, void** instance);
    JSValue LoadModuleByName(const std::string& moduleName, bool isAppModule, const std::string& param, const std::string& instanceName, void* instance);

    NativeValue* CreateDate(double time) override;
    NativeValue* CreateBigWords(int sign_bit, size_t word_count, const uint64_t* words) override;
    bool TriggerFatalException(NativeValue* error) override;
    bool AdjustExternalMemory(int64_t ChangeInBytes, int64_t* AdjustedValue) override;

    void StartCpuProfiler(const std::string fileName = "") override {}
    void StopCpuProfiler() override {}

    void ResumeVM() override {}
    bool SuspendVM() override
    {
        return false;
    }
    bool IsSuspended() override
    {
        return false;
    }
    bool CheckSafepoint() override
    {
        return false;
    }

    void DumpHeapSnapShot(const std::string &path, bool isVmMode = true, DumpFormat dumpFormat = DumpFormat::JSON) override {}
    bool BuildNativeAndJsBackStackTrace(std::string &stackTraceStr) override
    {
        return false;
    }
    bool StartHeapTracking(double timeInterval, bool isVmMode = true) override
    {
        return false;
    }
    bool StopHeapTracking(const std::string &filePath) override
    {
        return false;
    }

    void PrintStatisticResult() override {}
    void StartRuntimeStat() override {}
    void StopRuntimeStat() override {}
    size_t GetArrayBufferSize() override
    {
        return 0;
    }
    size_t GetHeapTotalSize() override
    {
        return 0;
    }
    size_t GetHeapUsedSize() override
    {
        return 0;
    }

    void RegisterUncaughtExceptionHandler(UncaughtExceptionCallback callback) override {}
    void HandleUncaughtException() override {}

private:
    JSRuntime* runtime_;
    JSContext* context_;
};

#endif /* FOUNDATION_ACE_NAPI_NATIVE_ENGINE_IMPL_QUICKJS_QUICKJS_NATIVE_ENGINE_H */
