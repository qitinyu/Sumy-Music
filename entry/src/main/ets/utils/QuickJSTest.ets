/**
 * QuickJS 引擎集成测试
 * 验证 QuickJS 引擎是否正常工作
 */
import { JSContext, JSValue } from '@devzeng/quickjs';

export class QuickJSTest {
  /** 运行基础测试 */
  static runBasicTest(): boolean {
    try {
      // 创建执行上下文
      const context = new JSContext();
      
      // 测试脚本执行
      const result = context.evaluateScript("'Hello QuickJS'");
      const resultStr = result.toString();
      
      // 释放资源
      result.release();
      context.release();
      
      console.info(`[QuickJSTest] Basic test result: ${resultStr}`);
      return resultStr === 'Hello QuickJS';
    } catch (e) {
      console.error('[QuickJSTest] Basic test failed:', e);
      return false;
    }
  }

  /** 测试对象操作 */
  static runObjectTest(): boolean {
    try {
      const context = new JSContext();
      
      // 创建对象
      const obj = JSValue.valueWithNewObject(context);
      const name = JSValue.valueWithString('test', context);
      obj.setValue(name, 'name');
      
      // 获取属性
      const retrievedName = obj.getProperty('name');
      const nameStr = retrievedName.toString();
      
      // 释放资源
      name.release();
      retrievedName.release();
      obj.release();
      context.release();
      
      console.info(`[QuickJSTest] Object test result: ${nameStr}`);
      return nameStr === 'test';
    } catch (e) {
      console.error('[QuickJSTest] Object test failed:', e);
      return false;
    }
  }

  /** 测试函数调用 */
  static runFunctionTest(): boolean {
    try {
      const context = new JSContext();
      
      // 定义函数
      const func = context.evaluateScript('(function(a, b) { return a + b; })');
      
      // 调用函数
      const arg1 = JSValue.valueWithNumber(10, context);
      const arg2 = JSValue.valueWithNumber(20, context);
      const result = func.callWithArguments([arg1, arg2]);
      
      // 检查结果
      const resultNum = result.toNumber();
      
      // 释放资源
      arg1.release();
      arg2.release();
      result.release();
      func.release();
      context.release();
      
      console.info(`[QuickJSTest] Function test result: ${resultNum}`);
      return resultNum === 30;
    } catch (e) {
      console.error('[QuickJSTest] Function test failed:', e);
      return false;
    }
  }

  /** 运行所有测试 */
  static runAllTests(): boolean {
    console.info('[QuickJSTest] Starting tests...');
    
    const basicTest = QuickJSTest.runBasicTest();
    const objectTest = QuickJSTest.runObjectTest();
    const functionTest = QuickJSTest.runFunctionTest();
    
    const allPassed = basicTest && objectTest && functionTest;
    
    console.info(`[QuickJSTest] Tests completed: basic=${basicTest}, object=${objectTest}, function=${functionTest}`);
    console.info(`[QuickJSTest] All tests passed: ${allPassed}`);
    
    return allPassed;
  }
}
