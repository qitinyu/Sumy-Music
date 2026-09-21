// Engine/Context Lifecycle
export const createEngine: () => bigint;
export const releaseEngine: (engineHandle: bigint) => void;
export const getGlobal: (engineHandle: bigint) => bigint;

// Value Factory
export const createUndefined: (engineHandle: bigint) => bigint;
export const createNull: (engineHandle: bigint) => bigint;
export const createBoolean: (engineHandle: bigint, value: boolean) => bigint;
export const createNumber: (engineHandle: bigint, value: number) => bigint;
export const createString: (engineHandle: bigint, value: string) => bigint;
export const createObject: (engineHandle: bigint) => bigint;
export const createArray: (engineHandle: bigint, length?: number) => bigint;
export const createError: (engineHandle: bigint, code: string, message: string) => bigint;
export const createDate: (engineHandle: bigint, timeMs: number) => bigint;

// Value Type Checks
export const isUndefined: (valueHandle: bigint) => boolean;
export const isNull: (valueHandle: bigint) => boolean;
export const isBoolean: (valueHandle: bigint) => boolean;
export const isNumber: (valueHandle: bigint) => boolean;
export const isString: (valueHandle: bigint) => boolean;
export const isObject: (valueHandle: bigint) => boolean;
export const isArray: (valueHandle: bigint) => boolean;
export const isDate: (valueHandle: bigint) => boolean;
export const isCallable: (valueHandle: bigint) => boolean;
export const isError: (valueHandle: bigint) => boolean;
export const isException: (valueHandle: bigint) => boolean;

// Value Conversion
export const toBooleanValue: (valueHandle: bigint) => boolean;
export const toNumberValue: (valueHandle: bigint) => number;
export const toStringValue: (valueHandle: bigint) => string;

// Property Access
export const getProperty: (engineHandle: bigint, objHandle: bigint, key: string) => bigint;
export const setProperty: (engineHandle: bigint, objHandle: bigint, key: string, valueHandle: bigint) => boolean;
export const hasProperty: (engineHandle: bigint, objHandle: bigint, key: string) => boolean;
export const deleteProperty: (engineHandle: bigint, objHandle: bigint, key: string) => boolean;
export const getPropertyNames: (engineHandle: bigint, objHandle: bigint) => bigint;
export const getElement: (engineHandle: bigint, arrayHandle: bigint, index: number) => bigint;
export const setElement: (engineHandle: bigint, arrayHandle: bigint, index: number, valueHandle: bigint) => boolean;
export const getArrayLength: (engineHandle: bigint, arrayHandle: bigint) => number;

// Function Call
export const callFunction: (engineHandle: bigint, thisHandle: bigint, funcHandle: bigint, args: bigint[]) => bigint;
export const construct: (engineHandle: bigint, constructorHandle: bigint, args: bigint[]) => bigint;

// Comparison
export const strictEquals: (valueHandle1: bigint, valueHandle2: bigint) => boolean;
export const looseEquals: (valueHandle1: bigint, valueHandle2: bigint) => boolean;
export const instanceOf: (valueHandle: bigint, constructorHandle: bigint) => boolean;

// Value Lifecycle
export const addRef: (valueHandle: bigint) => void;
export const release: (valueHandle: bigint) => void;

// Script Evaluation
export const evaluateScript: (engineHandle: bigint, script: string, sourceURL?: string) => bigint;

// Event Pump / Async
export const pumpJobs: (engineHandle: bigint, maxJobs?: number) => number;

// Error / Exception
export const getException: (engineHandle: bigint) => bigint;
export const throwException: (engineHandle: bigint, valueHandle: bigint) => bigint;
