---
title: "Python Unittest 单元测试框架基础"
date: 2020-10-15T16:34:38+08:00
draft: false
tags: 
  - unittest
categories: 
  - Test
---

#### 基本实例

```python
import unittest


class TestStringMethods(unittest.TestCase):

    def test_upper(self):
        self.assertEqual('foo'.upper(), 'FOO')

    def test_isupper(self):
        self.assertTrue('FOO'.isupper())
        self.assertFalse('Foo'.isupper())

    def test_split(self):
        s = 'hello world'
        self.assertEqual(s.split(), ['hello', 'world'])
        with self.assertRaises(TypeError):
            s.split(2)


if __name__ == '__main__':
    unittest.main()

```

运行：

```powershell
(autotest) ➜  myunittest python demo.py
...
----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
(autotest) ➜  myunittest python -m unittest -v demo.py
test_isupper (demo.TestStringMethods) ... ok
test_split (demo.TestStringMethods) ... ok
test_upper (demo.TestStringMethods) ... ok

----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
```

#### 命令行运行

可以通过命令行运行模块、类、和独立测试方法的测试：

```powershell
(autotest) ➜  myunittest python -m unittest demo
...
----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
(autotest) ➜  myunittest python -m unittest demo.TestStringMethods
...
----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
(autotest) ➜  myunittest python -m unittest demo.TestStringMethods.test_split
.
----------------------------------------------------------------------
Ran 1 test in 0.000s

OK
```

常用命令行选项：

| 参数           | 说明                                                         |
| -------------- | ------------------------------------------------------------ |
| -c, --catch    | 当测试正在运行，Control-C 会等待当前正在执行的用例执行完成再退出测试，并不会立即结束测试，再次按下 Control-C，引发平常的 KeyboardInterrupt 异常。 |
| -f, --failfast | 当出现第一个错误或失败时，停止运行测试。                     |
| -k             | 只运行匹配模式或子串的测试类和方法。可以多次使用这个选项，以便包含匹配子串的所有测试用例。 |

```powershell
(autotest) ➜  myunittest python -m unittest -c -v demo.py
test_isupper (demo.TestStringMethods) ... ok
test_split (demo.TestStringMethods) ... ^Cok

----------------------------------------------------------------------
Ran 2 tests in 10.003s

OK
(autotest) ➜  myunittest python -m unittest -v -k 'split' -k 'isupper' demo.py
test_isupper (demo.TestStringMethods) ... ok
test_split (demo.TestStringMethods) ... ok

----------------------------------------------------------------------
Ran 2 tests in 10.005s

OK
```

探索性测试 discover 可用选项：

| 参数                  | 说明                                         |
| --------------------- | -------------------------------------------- |
| -v, --verbose         | 更详细地输出结果。                           |
| -s, --start-derectory | 开始进行搜索的目录（默认值为当前目录`.`）。  |
| -p, --pattern         | 用于匹配测试文件的模式（默认为`test*.py`）。 |

```powershell
(autotest) ➜  myunittest python -m unittest discover

----------------------------------------------------------------------
Ran 0 tests in 0.000s

OK
(autotest) ➜  myunittest python -m unittest discover -p 'demo*.py'
...
----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
```

#### 测试集 TestSuite

根据所测功能，将测试用例集合起来，相同模块的 case 集合到一个 suite 。

```python
if __name__ == '__main__':
    # unittest.main()
    suite = unittest.TestSuite()
    suite.addTest(TestStringMethods('test_upper'))
    suite.addTests([TestStringMethods('test_isupper'), TestStringMethods('test_split')])

    runner = unittest.TextTestRunner(verbosity=2)
    runner.run(suite)
```

```powershell
(autotest) ➜  myunittest python test_demo.py
test_upper (__main__.TestStringMethods) ... ok
test_isupper (__main__.TestStringMethods) ... ok
test_split (__main__.TestStringMethods) ... ok

----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
```

其他向 suite 中添加用例的方式：

```python
# start.py
import unittest

suite = unittest.TestSuite()
# suite.addTests(unittest.TestLoader().discover('myunittest'))
suite.addTests(unittest.TestLoader().loadTestsFromName('myunittest.test_demo.TestStringMethods'))

runner = unittest.TextTestRunner(verbosity=2)
runner.run(suite)
```

```powershell
(autotest) ➜  cnblog-polo python start.py
test_isupper (myunittest.test_demo.TestStringMethods) ... ok
test_split (myunittest.test_demo.TestStringMethods) ... ok
test_upper (myunittest.test_demo.TestStringMethods) ... ok

----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
```

#### 跳过（skip）测试用例

```python
# test_skip.py
import sys
import unittest


def external_resource_available():
    return False


class MyTestCase(unittest.TestCase):

    @unittest.skip("nothing to test")
    def test_nothing(self):
        self.fail("shouldn't happen")

    @unittest.skipUnless(sys.platform.startswith("win"), "requires windows")
    def test_windowns_support(self):
        # 条件成立，执行测试
        pass

    @unittest.skipIf(sys.version_info.major == 2, "not supported in python major version 2")
    def test_only_on_python3(self):
        # 条件成立，不执行测试
        pass

    def test_maybe_skipped(self):
        if not external_resource_available():
            self.skipTest("external resource not available")
        # 待执行测试代码, 依赖 external_resource_available 结果为 True
        pass

```

```powershell
(autotest) ➜  myunittest python -m unittest -v test_skip.py
test_maybe_skipped (test_skip.MyTestCase) ... skipped 'external resource not available'
test_nothing (test_skip.MyTestCase) ... skipped 'nothing to test'
test_only_on_python3 (test_skip.MyTestCase) ... ok
test_windowns_support (test_skip.MyTestCase) ... skipped 'requires windows'

----------------------------------------------------------------------
Ran 4 tests in 0.000s

OK (skipped=3)
```

#### 测试用例执行前、执行后做特定操作

```python
import unittest


def setUpModule():
    print('模块级别的setup============')


def tearDownModule():
    print('模块级别的teardown==========')


class MyTestCase(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        print('类级别的setup========')

    @classmethod
    def tearDownClass(cls):
        print('类级别的teardown========')

    def setUp(self):
        print('方法级别的setup====')

    def tearDown(self):
        print('方法级别的teardown====')

    def test_add(self):
        self.assertFalse(1 + 1 == 3)

    def test_multi(self):
        self.assertTrue(2 * 3 == 6)
```

```powershell
(autotest) ➜  myunittest python -m unittest -v test_setup_teardown.py
模块级别的setup============
类级别的setup========
test_add (test_setup_teardown.MyTestCase) ... 方法级别的setup====
方法级别的teardown====
ok
test_multi (test_setup_teardown.MyTestCase) ... 方法级别的setup====
方法级别的teardown====
ok
类级别的teardown========
模块级别的teardown==========

----------------------------------------------------------------------
Ran 2 tests in 0.000s

OK
```

**参考：**[unittest 官方文档](https://docs.python.org/zh-cn/3.8/library/unittest.html)

