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

import { JSValue } from './JSValue';
import qjs from 'libquickjs.so';

export class JSContext {
  private _engineHandle: bigint = 0n;
  private nameValue: string = '';

  get engineHandle(): bigint {
    return this._engineHandle;
  }

  constructor() {
    this._engineHandle = qjs.createEngine();
  }

  get globalObject(): JSValue {
    const handle = qjs.getGlobal(this._engineHandle);
    return new JSValue(this, handle);
  }

  get exception(): JSValue | null {
    const handle = qjs.getException(this._engineHandle);
    if (handle === 0n) {
      return null;
    }
    return new JSValue(this, handle);
  }

  set exception(value: JSValue | null) {
    if (value !== null) {
      qjs.throwException(this._engineHandle, value.valueHandle);
    }
  }

  exceptionHandler?: (context: JSContext, exception: JSValue) => void;

  evaluateScript(script: string, sourceURL?: string): JSValue {
    const url = sourceURL ?? 'evaluate';
    const handle = qjs.evaluateScript(this.engineHandle, script, url);
    const value = new JSValue(this, handle);
    if (value.isException && this.exceptionHandler) {
      const exc = this.exception;
      if (exc) {
        this.exceptionHandler(this, exc);
      }
    }
    return value;
  }

  setObject(object: Record<string, number | string | boolean> | JSValue, name: string): void {
    if (object instanceof JSValue) {
      const globalObj = this.globalObject;
      qjs.setProperty(this.engineHandle, globalObj.valueHandle, name, object.valueHandle);
      globalObj.release();
    } else {
      const objHandle = qjs.createObject(this.engineHandle);
      for (const key of Object.keys(object)) {
        const val = object[key];
        if (typeof val === 'number') {
          const numHandle = qjs.createNumber(this.engineHandle, val);
          qjs.setProperty(this.engineHandle, objHandle, key, numHandle);
          qjs.release(numHandle);
        } else if (typeof val === 'string') {
          const strHandle = qjs.createString(this.engineHandle, val);
          qjs.setProperty(this.engineHandle, objHandle, key, strHandle);
          qjs.release(strHandle);
        } else if (typeof val === 'boolean') {
          const boolHandle = qjs.createBoolean(this.engineHandle, val);
          qjs.setProperty(this.engineHandle, objHandle, key, boolHandle);
          qjs.release(boolHandle);
        }
      }
      const globalObj = this.globalObject;
      qjs.setProperty(this.engineHandle, globalObj.valueHandle, name, objHandle);
      globalObj.release();
      qjs.release(objHandle);
    }
  }

  getGlobalProperty(name: string): JSValue {
    return this.globalObject.getProperty(name);
  }

  /**
   * 泵动 QuickJS 微任务/作业队列，让 pending 的 Promise 回调（await/then）落定。
   * 返回本次已执行的作业数；宿主在等待 async 插件结果时反复调用，直到返回 0。
   */
  pumpJobs(maxJobs?: number): number {
    if (this.engineHandle === 0n) {
      return -1;
    }
    return qjs.pumpJobs(this.engineHandle, maxJobs ?? 1000);
  }

  get name(): string {
    return this.nameValue;
  }

  set name(value: string) {
    this.nameValue = value;
  }

  release(): void {
    if (this.engineHandle !== 0n) {
      qjs.releaseEngine(this.engineHandle);
      this._engineHandle = 0n;
    }
  }
}
