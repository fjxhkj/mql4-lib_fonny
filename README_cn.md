# mql4-lib

MQL 专业开发者基础库.


## 简介

由MetaQuotes提供的MQL4/5编程语言是C++的一个非常有限版本，其标准库是（丑陋的）MFC的克隆，这两者都让我感到非常不舒服。大多数MQL4程序尚未适应MQL5（面向对象）的风格，更不用说可重用和优雅的组件化设计和编程了。

mql4-lib是一个简单的库，试图通过更面向对象的方法和类似Java的编码风格，使MQL编程更加愉快，并鼓励编写可重用的组件。该库有雄心成为MQL的事实基础库。

虽然该库最初针对MQL4，但它的大部分组件都与MQL5兼容。除了与交易相关的类之外，您可以在MetaTrader5上使用该库。该库旨在消除这一限制，使其成为一个真正的跨版本库，适用于MT4和MT5（以及x86/x64）。也许将来该库会改名为mql-lib。

## 安装

只需将库复制到您的 MetaTrader 数据文件夹的 `Include` 目录中，使用您选择的根目录名称即可，例如：

1. For MT4: `<MetaTrader Data>\MQL4\Include\Mql\<mql4-lib content>`.
2. For MT5: `<MetaTrader Data>\MQL5\Include\Mql\<mql4-lib content>`.

请注意，现在推荐的根目录名称是 `Mql`（Pascal Case）。以前是 `MQL4`，更适用于 MT4。实际上，该库的大部分功能也适用于 MT5，因此我已经开始将该库与两者兼容的过程。所有示例也将使用这个根目录名称。

建议您使用最新版本的 MetaTrader4/5，因为旧版本中许多功能不可用。

## 使用

该库处于早期阶段，但大多数组件都相当稳定，可以用于生产环境。以下是主要组件：

1. `Lang` 目录包含增强 MQL 语言的模块
2. `Collection` 目录包含有用的集合类型
3. `Format` 目录包含序列化格式的实现
4. `Charts` 目录包含多种图表类型和常用的图表工具
5. `Trade` 目录包含用于交易的有用抽象
6. `History` 目录包含用于历史数据的有用抽象
7. `Utils` 目录包含各种实用工具
8. `UI` 图表对象和用户界面控件（正在进行中）
9. `OpenCL` 为 MT4 带来 OpenCL 支持（正在进行中）

### 基础编程

在 `Lang` 中，我将三种程序类型（脚本、指标和专家顾问）抽象为三个基类，您可以继承这些基类。

基本上，您可以在一个可复用的类中编写您的程序，当您想要将它们用作独立的可执行文件时，您可以使用宏进行声明。

这些宏区分带有和不带有输入参数的程序。这是一个没有任何输入参数的简单脚本示例：

```c++
#include <Mql/Lang/Script.mqh>
class MyScript: public Script
{
public:
  // OnStart is now main
  void main() {Print("Hello");}
};

// declare it: notice second parameter indicates the script has no input
DECLARE_SCRIPT(MyScript,false)
```

这里是另一个示例，这次是一个带有输入参数的专家顾问（Expert Advisor）：

```c++
#include <Mql/Lang/ExpertAdvisor.mqh>

class MyEaParam: public AppParam
{
  ObjectAttr(string,eaName,EaName);
  ObjectAttr(double,baseLot,BaseLot);
public:
  // optionally override `check` method to validate paramters
  // this method will be called before initialization of EA
  // if this method returns false, then INIT_INCORRECT_PARAMETERS will
  // be returned
  // bool check(void) {return true;}
};

class MyEa: public ExpertAdvisor
{
private:
  MyEaParam *m_param;
public:
       MyEa(MyEaParam *param)
       :m_param(param)
      {
         // Initialize EA in the constructor instead of OnInit;
         // If failed, you call fail(message, returnCode)
         // both paramters of `fail` is optional, with default return code INIT_FAIL
         // if you don't call `fail`, the default return code is INIT_SUCCESS;
      }
      ~MyEa()
      {
         // Deinitialize EA in the destructor instead of OnDeinit
         // getDeinitReason() to get deinitialization reason
      }
  // OnTick is now main
  void main() {Print("Hello from " + m_param.getEaName());}
};

// The code before this line can be put in a separate mqh header

// We use macros to declare inputs
// Notice the trailing semicolon at the end of each INPUT, it is needed
// support custom display name because of some unknown rules from MetaQuotes
BEGIN_INPUT(MyEaParam)
  INPUT(string,EaName,"My EA"); // EA Name (Custom display name is supported)
  INPUT(double,BaseLot,0.1);    // Base Lot
END_INPUT

DECLARE_EA(MyEa,true)  // true to indicate it has parameters
```

`ObjectAttr` 宏为一个类声明了标准的获取和设置方法。只需遵循 Java Beans(TM) 约定即可。

我使用了一些宏技巧来解决 MQL 的限制。当我有时间时，我会详细记录该库的文档。

通过这种方法，您可以编写可重用的 EA、脚本或指标。您不需要担心 OnInit、OnDeinit、OnStart、OnTick、OnCalculate 等函数。您永远不直接在 EA 中使用输入参数。您可以编写一个基础 EA，并轻松扩展它。

### 运行时可控指标（Runtime Controlled Indicators）和指标驱动器（Indicator Drivers）

当您使用这个库创建一个指标时，它可以作为独立的指标（由终端运行时控制），也可以由您的程序驱动。这是一个强大的概念，因为您可以编写一次指标代码，然后在 EA、脚本或作为独立指标中使用它。您可以将指标用于普通的时间序列图表，也可以让它由派生自 `HistoryData` 的类（如 TimeSeriesData、Renko 或 TimeFrame）驱动。

让我以一个示例指标 `DeMarker` 来展示给您。首先，我们在一个名为 `DeMarker.mqh` 的头文件中定义了通用的可复用指标模块。

```c++
#property strict

#include <Mql/Lang/Mql.mqh>
#include <Mql/Lang/Indicator.mqh>
#include <MovingAverages.mqh>
//+------------------------------------------------------------------+
//| Indicator Input                                                  |
//+------------------------------------------------------------------+
class DeMarkerParam : public AppParam
{
  ObjectAttr(int, AvgPeriod, AvgPeriod); // SMA Period
};
//+------------------------------------------------------------------+
//| DeMarker                                                         |
//+------------------------------------------------------------------+
class DeMarker : public Indicator
{
private:
  int m_period;

protected:
  double ExtMainBuffer[];
  double ExtMaxBuffer[];
  double ExtMinBuffer[];

public:
  //--- this provides time series like access to the indicator buffer
  double operator[](const int index) { return ExtMainBuffer[ArraySize(ExtMainBuffer) - index - 1]; }

  DeMarker(DeMarkerParam *param)
      : m_period(param.getAvgPeriod())
  {
    //--- runtime controlled means that it is used as a standalone Indicator controlled by the Terminal
    //--- isRuntimeControlled() is a method of common parent class `App`
    if (isRuntimeControlled())
    {
      //--- for standalone indicators we set some options for visual appearance
      string short_name;
      //--- indicator lines
      SetIndexStyle(0, DRAW_LINE);
      SetIndexBuffer(0, ExtMainBuffer);
      //--- name for DataWindow and indicator subwindow label
      short_name = "DeM(" + IntegerToString(m_period) + ")";
      IndicatorShortName(short_name);
      SetIndexLabel(0, short_name);
      //---
      SetIndexDrawBegin(0, m_period);
    }
  }

  int main(const int total,
           const int prev,
           const datetime &time[],
           const double &open[],
           const double &high[],
           const double &low[],
           const double &close[],
           const long &tickVolume[],
           const long &volume[],
           const int &spread[])
  {
    //--- check for bars count
    if (total < m_period)
      return (0);
    if (isRuntimeControlled())
    {
      //--- runtime controlled buffer is auto extended and is by default time series like
      ArraySetAsSeries(ExtMainBuffer, false);
    }
    else
    {
      //--- driven by yourself and thus the need to resize the main buffer
      if (prev != total)
      {
        ArrayResize(ExtMainBuffer, total, 100);
      }
    }
    if (prev != total)
    {
      ArrayResize(ExtMaxBuffer, total, 100);
      ArrayResize(ExtMinBuffer, total, 100);
    }
    ArraySetAsSeries(low, false);
    ArraySetAsSeries(high, false);

    int begin = (prev == total) ? prev - 1 : prev;

    for (int i = begin; i < total; i++)
    {
      if (i == 0)
      {
        ExtMaxBuffer[i] = 0.0;
        ExtMinBuffer[i] = 0.0;
        continue;
      }
      if (high[i] > high[i - 1])
        ExtMaxBuffer[i] = high[i] - high[i - 1];
      else
        ExtMaxBuffer[i] = 0.0;

      if (low[i] < low[i - 1])
        ExtMinBuffer[i] = low[i - 1] - low[i];
      else
        ExtMinBuffer[i] = 0.0;
    }
    for (int i = begin; i < total; i++)
    {
      if (i < m_period)
      {
        ExtMainBuffer[i] = 0.0;
        continue;
      }
      double smaMax = SimpleMA(i, m_period, ExtMaxBuffer);
      double smaMin = SimpleMA(i, m_period, ExtMinBuffer);
      ExtMainBuffer[i] = smaMax / (smaMax + smaMin);
    }

    //--- OnCalculate done. Return new prev.
    return (total);
  }
};
```

如果您想将其作为独立指标使用，请创建 `DeMarker.mq4` 文件：

```c++
#property copyright "Copyright 2017, Li Ding"
#property link "dingmaotu@hotmail.com"
#property version "1.00"
#property strict

#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 1.0
#property indicator_buffers 1
#property indicator_color1 LightSeaGreen
#property indicator_level1 0.3
#property indicator_level2 0.7
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

#include <Indicators/DeMarker.mqh>
//--- input parameters
BEGIN_INPUT(DeMarkerParam)
INPUT(int, AvgPeriod, 14); // Averaging Period
END_INPUT

DECLARE_INDICATOR(DeMarker, true);
```

或者，如果您想在 EA 中使用它，并由 Renko 图表驱动：
```c++
//--- code snippets for using an indicator with Renko

//--- OnInit
//--- create the indicator manually, its runtime controlled flag is false by default
DeMarkerParam *param = new DeMarkerParam;
param.setAvgPeriod(14);
deMarker = new DeMarker(param);

//--- HistoryData::OnUpdate is an event that can be subscribed by Indicators
renko = new Renko(_Symbol, 300);
//--- add indicator to the driver: you can add multiple indicators
//--- the OnUpdate event will delete its subscribers when destructed
renko.OnUpdate += deMarker;
//--- create the real driver that provide history data

//--- OnTick
renko.update(Close[0]);

//--- after update, all indicators attached to the renko.OnUpdate event will be updated
//--- access DeMarker
double value = deMarker[0];

//--- OnDeinit
//--- need to release resources
delete renko;
```

### 事件处理

专家顾问（Expert Advisors）和指标（Indicators）可以接收图表上的事件，并且它们继承自 `EventApp` 类，该类提供了便捷处理事件的功能。

默认情况下，`EventApp` 通过不做任何操作来处理所有事件。您甚至可以创建一个空的 EA 或指标，如果您愿意的话：

```MQL5
#include <Mql/Lang/ExpertAdvisor.mqh>

class MyEA: public ExpertAdvisor {};

DECLARE_EA(MyEA,false)
```

如果您创建的是一个纯粹的 UI 应用程序，或者仅仅是对外部事件做出响应，这将非常有用。您不需要一个主方法，只需要处理您感兴趣的内容即可。

```MQL5
#include <Mql/Lang/ExpertAdvisor.mqh>
class TestEvent: public ExpertAdvisor
  {
public:
   void              onAppEvent(const ushort event,const uint param)
     {
      PrintFormat(">>> External event from DLL: %u, %u",event,param);
     }
     
   void              onClick(int x, int y)
     {
      PrintFormat(">>> User clicked on chart at position (%d,%d)", x, y);
     }
     
   void              onCustom(int id, long lparam, double dparam, string sparam)
     {
      //--- `id` is the SAME as the second parameter of ChartEventCustom,
      //--- no need to minus CHARTEVENT_CUSTOM, the library does it for you
      PrintFormat(">>> Someone has sent a custom event with id %d", id);
     }
  };
DECLARE_EA(TestEvent,false)
```

### 外部事件

`Lang/Event` 模块提供了一种从 MetaTrader 终端运行时以外（例如从 DLL）发送自定义事件的方法。

您需要调用 `PostMessage/PostThreadMessage` 函数，并以与 `EncodeKeydownMessage` 使用相同算法进行编码的方式传递参数。然后，任何派生自 EventApp 的程序都可以在其 `onAppEvent` 事件处理程序中处理此消息。

以下是一个 C 语言的示例实现：

```C
#include <Windows.h>
#include <stdint.h>
#include <limits.h>

static const int WORD_BIT = sizeof(int16_t)*CHAR_BIT;

void EncodeKeydownMessage(const WORD event,const DWORD param,WPARAM &wparam,LPARAM &lparam)
{
    DWORD t=(DWORD)event;
    t<<= WORD_BIT;
    t |= 0x80000000;
    DWORD highPart= param & 0xFFFF0000;
    DWORD lowPart = param & 0x0000FFFF;
    wparam = (WPARAM)(t|(highPart>>WORD_BIT));
    lparam = (LPARAM)lowPart;
}

BOOL MqlSendAppMessage(HWND hwnd, WORD event, DWORD param)
{
    WPARAM wparam;
    LPARAM lparam;
    EncodeKeydownMessage(event, param, wparam, lparam);
    return PostMessageW(hwnd,WM_KEYDOWN,wparam, lparam);
}
```

该机制使用自定义的 WM_KEYDOWN 消息来触发 OnChartEvent。在 `OnChartEvent` 处理程序中，`EventApp` 检查 KeyDown 事件是否实际上是来自其他源（而不是真正的按键按下）的自定义应用程序事件。如果是，则 `EventApp` 调用其 `onAppEvent` 方法。

这种机制有一定的限制：参数只是一个整数（32位），这是由于 MetaTrader 终端中如何处理 WM_KEYDOWN 的方式所决定的。而且这个解决方案可能在64位的 MetaTrader5 中无法工作。

尽管有这些限制，但这实际上使您摆脱了 MetaTrader 的限制：您可以随时发送事件并让 mt4 程序处理它，而无需在 OnTimer 中进行轮询，或者在 OnTick 中创建管道/套接字，这是大多数 API 封装程序的工作方式。

使用 OnTimer 不是一个好主意。首先，它无法从 MQL 方面接收任何参数。您至少需要一个事件的标识符。其次，`WM_TIMER` 事件在主线程中非常拥挤。即使在没有数据到达的周末，`WM_TIMER` 仍然会不断发送到主线程。这会导致执行更多的指令来判断它是否是程序的有效事件。

*警告*：这是一个临时解决方案。处理异步事件的最佳方法是找出 ChartEventCustom 是如何实现的，并在 C/C++ 中实现它，但这非常困难，因为它不是通过 win32 消息实现的，而且由于非常强大的反调试措施，您无法查看其内部实现。

在 MetaTrader 终端内部，最好使用 ChartEventCustom 来发送自定义事件。

### 集合

在高级的 MQL 程序中，您需要使用更复杂的集合类型来进行订单管理。

这个包计划将常见的集合类型添加到库中，包括列表、哈希映射、树等等。

目前有两种列表类型：

1. `Collection/LinkedList` 是链表的实现。
2. `Collection/Vector` 是基于数组的实现。

> Vector (ArrayList) 适合查找，LinkedList 适合增删.
>
> 对于简单且长度较短的集合，即使进行频繁的插入和删除操作，基于数组的实现可能更快且开销较小。

另外还有两种 `Set` 实现:

1. 基于数组的 `Collection/ArraySet`
2. 基于哈希的 `Collection/HashSet`

借助类模板和继承，我实现了一个层次结构:

    ConstIterable -> Iterable -> Collection -> List -> Vector (like ArrayList in Java)
                                                    -> LinkedList
                                            -> Set  -> ArraySet
                                                    -> HashSet

`List` 添加了一些重要的方法，例如通过索引访问元素，以及类似于 `stack` 和 `queue` 的方法（如 `push`、`pop`、`shift`、`unshift` 等）。

`Set` 基本上与 `Collection` 相同，只是增加了一些集合操作（如并集、交集等）。

我想指出一些非常有用但未记录在案的 MQL4/5 特性：

```
1. 类模板（！）
2. typedef函数指针（！）
3. 模板函数重载
4. 联合类型
```

尽管目前无法继承多个接口，但我认为将来可能会实现这一功能。

在这些特性中，`类模板`是最重要的，因为它可以极大地简化集合代码。这些特性被 MetaQuotes 用于将.Net 正则表达式库移植到 MQL。

常见用法如下:

```c++
LinkedList<Order*> orderList; // 基于链表的实现，插入和删除更快。

LinkedList<int> intList; // 是的，它也支持基本类型。

Vector<Order*>; orderVector // 基于数组的实现，随机访问更快。
    
Vector<int> intVector;
```

要遍历一个集合，请使用其迭代器，因为迭代器知道最高效的遍历方式。

还有两个用于迭代的宏：`foreach` 和 `foreachv`。在循环中可以使用 `break` 和 `return`，而不必担心资源泄漏，因为我们使用 `Iter` RAII 类来包装迭代器指针。

以下为用 `LinkedList` 管理历史订单记录的例子:

```c++
//+------------------------------------------------------------------+
//|                                                TestOrderPool.mq4 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016-2017, Li Ding"
#property link "dingmaotu@hotmail.com"
#property version "1.00"
#property strict

#include <Mql/Trade/Order.mqh>
#include <Mql/Trade/OrderPool.mqh>
#include <Mql/Collection/LinkedList.mqh>

class ProfitHisOrderPool : public HistoryPool
{
private:
public:
  ProfitHisOrderPool(){};
  ~ProfitHisOrderPool(){};
  bool matches() const { return Order::Profit() > 0; }
};

// 更多用法请参考源码以及 mt4-lib 项目的 readme_cn.md

void OnStart()
{
  LinkedList<Order *> list;
  ProfitHisOrderPool pool;
  if (pool.count() < 1)
  {
    PrintFormat("*** %s, 无任何历史订单!", __FUNCTION__);
    return;
  }

  PrintFormat("*** %s, 列出历史订单池共 %i 条记录.", __FUNCTION__, pool.count());

  foreachorder(pool)
  {
    // 用于对比 Order.toString()
    OrderPrint();
    list.push(new Order());
  }

  PrintFormat("*** %s, 已加入到 list 中的元素数量: %d", __FUNCTION__, list.size());

  Order *o = list.get(0);
  PrintFormat("*** %s, get(0) 到的元素 oTicket: %i", __FUNCTION__, o.getTicket());

  // 删除元素,如果已知序号,也可以用 list.removeAt(0)
  Order *o2 = list.shift();
  PrintFormat("*** %s, shift 到被删除的元素 oTicket: %i", __FUNCTION__, o2.getTicket());

  PrintFormat("*** %s, 删除首个元素成功,现在 list 中的元素的数量: %d", __FUNCTION__, list.size());

  // 查看列表的头部元素
  list.push(o);
  PrintFormat("*** %s, 将 get(0) 得到的元素再加回去list中, 现在集合中的数量: %d", __FUNCTION__, list.size());

  // 以下为各种遍历list的方法

  // // Iter RAII class
  // for (Iter<Order *> it(list); !it.end(); it.next())
  // {
  //   Order *o = it.current();
  //   Print(o.toString());
  // }

  // // foreach macro: use it as the iterator variable
  // foreach (Order *, list)
  // {
  //   Order *o = it.current();
  //   Print(o.toString());
  // }

  // foreachv macro: declare element varaible o in the second parameter
  foreachv(Order *, oInfo, list)
  {
    Print(oInfo.toString());
  }

  PrintFormat("*** %s, 测试结束!", __FUNCTION__);
}

```

### HashMap 字典和映射

对于任何复杂的程序来说，映射（或字典）非常重要。Mql4-lib 使用 Murmur3 字符串哈希算法实现了一个高效的哈希映射。该实现遵循 CPython3 的哈希算法，并保持插入顺序。

您可以使用任何内置类型作为键，包括任何类指针。这些类型的哈希函数已在 `Lang/Hash` 模块中实现。

`HashMap` 接口非常简单。以下是一个简单的示例，用于统计著名歌剧《哈姆雷特》中的单词数量：

```c++
#include <Mql/Lang/Script.mqh>
#include <Mql/Collection/HashMap.mqh>
#include <Mql/Utils/File.mqh>

class CountHamletWords : public Script
{
public:
  void main()
  {
    TextFile txt("hamlet.txt", FILE_READ);
    if (txt.valid())
    {
      // 初始化 HashMap
      HashMap<string, int> wordCount;
      while (!txt.end() && !IsStopped())
      {
        string line = txt.readLine();
        string words[];
        StringSplit(line, ' ', words);
        int len = ArraySize(words);
        if (len > 0)
        {
          for (int i = 0; i < len; i++)
          {
            int newCount = 0;
            if (!wordCount.contains(words[i]))
              newCount = 1;
            else
              newCount = wordCount[words[i]] + 1;
            wordCount.set(words[i], newCount);
          }
        }
      }
      Print("Total words: ", wordCount.size());
      //--- you can use the foreachm macro to iterate a map
      foreachm(string, word, int, count, wordCount)
      {
        PrintFormat("%s: %d", word, count);
      }
    }
  }
};
DECLARE_SCRIPT(CountHamletWords, false)
```

在最近的更新（2017-11-28）之后，Map 迭代器不再是 const，并支持两个额外的操作：`remove` 和 `replace (setValue)`。因此，在之前的版本中，如果要从映射中移除某些元素，您必须将键存储在其他位置，并稍后删除这些键。这既不优雅也不高效。以下示例展示了这种差异：

```c++
HashMap<int, int> m;

//--- 更新之前
Vector<int> v;
foreachm(int, key, int, value, m)
{
  if (value % 2 == 0)
    v.push(key);
}
foreachv(int, key, v)
{
  m.remove(key);
}

//--- 更新之后
foreachm(int, key, int, value, m)
{
  if (value % 2 == 0)
    it.remove();
}
```

### 文件系统和IO

MQL 文件函数的设计直接操作三种类型的文件：二进制文件、文本文件和 CSV 文件。对我来说，这些文件类型应该形成一个分层关系：CSV 是一个特殊的文本文件，而文本文件则是二进制文件的特殊形式（包括文本的编码和解码）。但是，MQL 文件函数的设计并不是这样的，它允许不同的函数在不同类型的文件上进行操作，导致了混乱的局面。例如，`FileReadString` 函数的行为完全取决于它所操作的文件类型：对于二进制文件，它会读取指定长度的 Unicode 字节（UTF-16 LE），对于文本文件，它会读取整行（如果设置了 FILE_ANSI 标志，则根据代码页解码文本），对于 CSV 文件，它只会读取一个字符串字段。我不喜欢这种设计，也没有精力和时间去重新实现文本编码 / 解码和类型序列化 / 反序列化的功能。

因此，我编写了一个 `Utils/File` 模块，使用更清晰的接口封装了所有的文件函数，但没有改变整个设计。这个模块包含了五个类：`File` 是一个基类，但不能直接实例化；`BinaryFile`、`TextFile` 和 `CsvFile` 是继承自基类的子类，你可以在你的代码中使用它们；还有一个有趣的类 `FileIterator`，它实现了标准的 `Iterator` 接口，你可以使用相同的技术遍历目录中的文件。

这里是一个关于 TextFile 和 CsvFile 的示例：

```c++
#include <Mql/Utils/File.mqh>

void OnStart()
{
  File::createFolder("TestFileApi");

  TextFile txt("TestFileApi\\MyText.txt", FILE_WRITE);
  txt.writeLine("你好，世界。");
  txt.writeLine("Hello world.");

  //--- reopen closes the current file handle first
  txt.reopen("TestFileApi\\MyText.txt", FILE_READ);
  while (!txt.end())
  {
    Print(txt.readLine());
  }

  CsvFile csv("TestFileApi\\MyCsv.csv", FILE_WRITE);
  //--- write whole line as a text file
  csv.writeLine("This,is one,CSV,file");

  //--- write fields one by one
  csv.writeString("这是");
  csv.writeDelimiter();
  csv.writeInteger(1);
  csv.writeDelimiter();
  csv.writeBool(true);
  csv.writeDelimiter();
  csv.writeString("CSV");
  csv.writeNewline();

  csv.reopen("TestFileApi\\MyCsv.csv", FILE_READ);
  for (int i = 1; !csv.end(); i++)
  {
    Print("Line ", i);
    //--- notice that you SHALL NOT directly use while(!csv.isLineEnding()) here
    //--- or you will run into a infinite loop
    do
    {
      Print("Field: ", csv.readString());
    } while (!csv.isLineEnding());
  }
```

然后看看如何使用 `FileIterator`:

```c++
#include <Mql/Utils/File.mqh>

int OnStart()
{
  for (FileIterator it("*"); !it.end(); it.next())
  {
    string name = it.current();
    if (File::isDirectory(name))
    {
      Print("Directory: ", name);
    }
    else
    {
      Print("File: ", name);
    }
  }
}
```

或者你可以使用强大的 `foreachfile` 宏来实现更高级的功能：

```c++
#include <Mql/Utils/File.mqh>

int OnStart()
{
  //--- first parameter is the local variable *name* for current file name
  //--- second parameter is the filter pattern string
  foreachfile(name, "*")
  {
    if (File::isDirectory(name))
      Print("Directory: ", name);
    else
      Print("File: ", name);
  }
}
```

还有一种特殊类型的文件称为历史文件。它们是支持 MetaTrader 图表显示的文件。有一个专门用于打开历史文件的函数：`HistoryFileOpen`，而历史文件具有固定的结构。我在 `Utils/HistoryFile` 类中封装了对历史文件的操作。这个组件在实现自定义图表类型（如离线图表）时非常有用。您可以在 `Chart/PriceBreakChart` 或 `Chart/RenkoChart` 中看到示例用法。

### 序列化格式

拥有一些快速可靠的序列化格式非常有用，可以用于持久化、消息传递等。有很多选项：JSON、ProtoBuf 等等。然而，在 MQL 中实现它们有些困难。以 JSON 为例，您必须使用类似于 Map 或 Dictionary 的数据结构来实现对象，甚至解析一个数字都不是一件容易的事情（请参阅 JSON 规范）。而且，我真的不喜欢每次接收一个简单的 JSON 时都要创建一个字典。ProtoBuf 更加困难，因为您需要实现一个 ProtoBuf 编译器来为 MQL 生成代码。

当我决定重新编写 mql4-redis 绑定时，我计划制作一个纯粹的 MQL Redis 客户端。因此，我开始了解并实现了 `REdis Serialization Protocol` (RESP)。它非常简单但足够有用。它具有字符串、整数、数组、批量字符串（字节）和 nil 等数据类型。因此，我在 MQL 中实现了这些类型，并制作了完整的编码器/解码器。

我将其放在这个通用库中，而不是 mql-redis 客户端，因为它是一个可重用的组件。想象一下，您可以将值序列化到缓冲区中，并使用 ZeroMQ 将它们作为消息发送。我将在本节中解释 RESP 协议组件的用法。

要使用 RESP 协议，您需要包含 `Mql/Format/Resp.mqh`。值类型非常直观：

```c++
#include <Mql/Lang/Resp.mqh>
// RespValue 是所有值的父类，它具有一些通用方法，所有类型都实现了这些方法，它们包括：encode、toString 和 getType。
string GetEncodedString(const RespValue &value)
{
  char res[];
  value.encode(res, 0);
  RespBytes bytes(res);
  // RespBytes 的 toString 方法将字节内容打印为可读的字符串，并正确进行转义处理。
  return bytes.toString();
}

void OnStart()
{
  // 创建一个预先分配了 7 个元素的数组。
  RespArray a(7);
  a.set(0, new RespBytes("set"));
  a.set(1, new RespBytes("x"));
  a.set(2, new RespBytes("10"));           // 批量字符串（可以包含字符串中的空格、换行符等）。
  a.set(3, new RespError("ERROR test!"));  // 与 RespString 相同，但表示一个错误。
  a.set(4, new RespString("abd akdfa\"")); // RespString 对应 hiredis 的 REPLY_STATUS 类型。
  a.set(5, new RespInteger(623));
  a.set(6, RespNil::getInstance()); // RespNil 是一个单例类型

  Print(a.toString()); // 打印数组的人类可读表示。
  Print(GetEncodedString(a));

  char res[];
  a.encode(res, 0);

  int encodedSize = ArraySize(res);
  RespMsgParser msgParser; // RespMsgParser 解析一个包含完整输入的缓冲区。
  RespValue *value = RespParser::parse(res, 0);
  Print(parser.getPosition() == encodedSize);
  Print(value.getType() == TypeArray);
  Ptr<RespArray> b(dynamic_cast<RespArray *>(value));
  Print(b.r.size() == 7);
}
```

如上所示的代码，您可以任意组合值并将它们编码到缓冲区中。您可以无限嵌套数组。值类型提供了各种操作的非常有用的方法。您可以在相应的源文件中找到更多信息。

我为该协议编写了两个解析器。第一个解析器用于面向消息的上下文，您接收到整个缓冲区后开始解析。该类名为 `RespMsgParser`。另一个解析器名为 `RespStreamParser`，用于面向流的上下文，您可能会部分接收到缓冲区并开始解析。它会告诉您是否需要更多输入，并且您可以在提供更多输入时恢复解析。后一个解析器受到了 hiredis 的 `ReplyReader` 实现的启发。

这两个解析器都有一个 `getError` 方法，用于告诉您出了什么问题（请参阅 `Mql/Format/RespParseError.mqh` 获取所有错误代码），如果 `parse` 方法返回一个空值。`RespMsgParser` 还有一个 `check` 方法，可以检查给定的缓冲区是否包含有效的 `RespValue`，而无需实际创建它。`check` 方法也会设置错误标志，就像 `parse` 方法一样。

这两个解析器都没有像 hiredis 的 `ReplyReader` 那样的嵌套限制。只有您计算机的内存（或 MetaTrader 的堆栈）是限制。但总体而言，`ReplyReader` 的速度会比我的解析器更快。它是用 C 编写的，并且使用静态数组保持堆栈。而且它的目标不是成为一个通用的编码/解码库。

### 访问订单

在大多数 MQL4 程序中，您可以通过 `OrdersHistoryTotal`、`OrdersTotal` 和 `OrderSelect` 来访问订单。代码通常会变得混乱，因为您需要过滤特定的订单。基本的逻辑如下：

```MQL5
int total = OrdersTotal();

for(int i=0; i<total; i++)
{
  if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
  if(!MatchesWhateverPredicatesYouSet()) continue;
  DoSomethingYouWantWithTheOrder();
}
```

关键是，订单过滤代码通常是可重用的，您不希望每次需要过滤订单时都要重写它。

因此，在 `Trade/Order` 和 `Trade/OrderPool` 模块中，我提供了一个 OrderPool 类，您可以派生它，并提供了一个方便的迭代器来封装上述访问订单的约定。以下是一个示例，展示了基本的用法：

```c++
#include <Mql/Trade/OrderPool.mqh>

// 仅匹配历史订单池中的盈利订单。
class ProfitHistoryPool : public HistoryPool
{
public:
  bool matches() const { return Order::Profit() > 0; }
};

void OnStart()
{
  ProfitHistoryPool profitPool;
  // the foreachorder macro can iterate order pools for you
  // and take care of order filtering
  // both pointers and references are accepted
  foreachorder(profitPool)
  {
    //--- here you can directly use Order* function like this:
    //--- OrderPrint();
    //--- or create an Order class
    Order o;
    Print(o.toString());
  }
}
```

### 语义化的对称订单操作

我所说的 "语义化的对称订单 *symetric order semantics*"是什么意思？考虑以下代码，逐步设置追踪止损，直到订单处于保本状态：

```c++
// 以下是一个用于说明的部分代码；如果您没有其他代码，它无法运行
// M_POINT 是一个常量（当前符号的点值）
void TrailToBreakeven(const Order &order, OrderAttributes &attr)
{
  //--- 检查是否获利超过 InpBreakevenPoints
  bool isSetStopLoss = false;
  double stopLossLevel = 0.0;

  if (order.getStopLoss() > 0)
  {
    if (order.getType() == OP_BUY)
    {
      if (order.getStopLoss() < order.getOpenPrice())
      {
        double profitPrice = m_symbol.getBid() - order.getOpenPrice() - InpBreakevenPoints * M_POINT;
        if (profitPrice > 0)
        {
          if (InpBreakevenStep > 0)
          {
            int factor = int(profitPrice / (InpBreakevenStep * M_POINT));
            if (factor > 0)
            {
              double sl = attr.getOriginalStoploss() + InpBreakevenPoints * M_POINT * factor;
              if (sl > order.getStopLoss())
              {
                isSetStopLoss = true;
                if (sl > order.getOpenPrice())
                {
                  stopLossLevel = NormalizeDouble(order.getOpenPrice() + M_POINT, M_DIGITS);
                }
                else
                {
                  stopLossLevel = NormalizeDouble(sl, M_DIGITS);
                }
              }
            }
          }
          else
          {
            isSetStopLoss = true;
            stopLossLevel = NormalizeDouble(order.getOpenPrice() + M_POINT, M_DIGITS);
          }
        }
      }
    }
    else
    {
      if (order.getStopLoss() > order.getOpenPrice())
      {
        double profitPrice = order.getOpenPrice() - InpBreakevenPoints * M_POINT - m_symbol.getAsk();
        if (profitPrice > 0)
        {
          if (InpBreakevenStep > 0)
          {
            int factor = int(profitPrice / (InpBreakevenStep * M_POINT));
            if (factor > 0)
            {
              double sl = attr.getOriginalStoploss() - InpBreakevenPoints * M_POINT * factor;
              if (sl < order.getStopLoss())
              {
                isSetStopLoss = true;
                if (sl < order.getOpenPrice())
                {
                  stopLossLevel = NormalizeDouble(order.getOpenPrice() - M_POINT, M_DIGITS);
                }
                else
                {
                  stopLossLevel = NormalizeDouble(sl, M_DIGITS);
                }
              }
            }
          }
          else
          {
            isSetStopLoss = true;
            stopLossLevel = NormalizeDouble(order.getOpenPrice() - M_POINT, M_DIGITS);
          }
        }
      }
    }
  }
  if (isSetStopLoss)
  {
    if (OrderModify(order.getTicket(), 0, stopLossLevel, 0, 0, clrNONE))
    {
      PrintFormat(">>> Setting order #%d stoploss to %f",
                  order.getTicket(), stopLossLevel);

      if ((order.getType() == OP_BUY && stopLossLevel >= order.getOpenPrice()) ||
          (order.getType() == OP_SELL && stopLossLevel <= order.getOpenPrice()))
      {
        attr.setState(Breakeven);
      }
    }
    else
    {
      Alert(StringFormat(">>> Error setting order #%d stoploss %f",
                         order.getTicket(), stopLossLevel));
    }
  }
}
```

这在日常的 EA 开发中非常典型。您可以看到，对于买入和卖出订单，逻辑是相同的。但是代码必须分别编写，因为它们之间存在足够的差异。而且很难确定您正在使用哪种逻辑，因为它们深埋在计算细节中。这样编写容易出错，因为在复制几乎相同的代码时，您可能会忘记更改一些减号或加号。此外，我们经常使用价格格式化、点值到绝对价格差的转换以及价格归一化等操作。如果我们只需要清晰地编写逻辑一次，然后自动处理买入和卖出订单，会怎么样呢？

解决方案就是“对称订单语义”：它是 `Order` 类中一组方法（包括实例方法和静态方法）。这些方法名非常简单（我故意将它们缩短），每个方法都表达了一个订单的通用语义，不论其类型如何。我将在下面列出基本操作，并稍后展示如何使用它们。

1. 格式化和转换

有三个操作支持基于订单符号对价格值进行格式化和转换。

    * f(p)：将价格 `p` 格式化为字符串，考虑到符号的小数位数。
    * n(p)：将价格 `p` 根据符号的小数位数标准化的 double 类型。
    * ap(p)：获取以点值 `p`（int 类型）为基础的绝对价格差（double 类型）。正数表示盈利,负数表示亏损,而无需考虑开仓的方向.

2. 当前报价

根据订单类型获取相应的 `ask卖出/bid买入` 价值非常常见。
对于买单，使用卖出价(ask)开仓，使用买入价(bid)平仓；而对于卖单，则相反。我提供了两个基本操作来获取这个值。

    * s()：获取正确的价格以开始一个订单。
    * e()：获取正确的价格以结束一个订单。

3. 价格计算

提供了两种方法进行价格计算:

- `p(s,e)` 用于计算以开始价格 `s` 和结束价格 `e` 为基础，获取绝对价格差作为盈利。要获取亏损，只需使用 `-p(s,e)` 或 `p(e,s)`；前者更可取，因为它更清晰地表示*盈利*的相反情况。
- `pp(p,pr)` 用于计算从 `p` 开始，并希望盈利 `pr` 的金额，可获取目标价格。如果我们希望亏损 `pr` 的金额，则使用 `pp(p,-pr)`。

`pp` 还有有一个重载方法, 其中 `pr` 参数以点值( `int` 类型 )表示,这只是为了方便使用,并不影响语义.

有了这些基本操作，我们可以对一个订单的大多数语义进行对称表达。例如: 

表达"止损点是否盈利", 可使用:

```c++
order.p(order.getOpenPrice(), order.getStoploss()) >= 0
```

我们可以从字面上理解为 "如果我们从开仓价格移动到止损价格，我们仍然盈利"。这样，您只需编写一套规则并清晰地表达它。

我将尝试使用*对称订单语义*来重新编写本节开头的示例。请仔细阅读并将其与第一个示例进行比较。看看代码长度如何大大减少，意图变得非常清晰。

```c++
// 以下是用于说明目的的部分代码；如果您没有其他代码，它将无法运行。
void TrailToBreakeven(const Order &o, OrderAttributes &attr)
{
  // 检查是否盈利超过了 InpBreakevenPoints（输入的盈亏平衡点数）。
  bool isSetStopLoss = false;
  double stopLossLevel = 0.0;

  if (o.getStopLoss() > 0)
  {
    //--- if not breakeven
    if (o.p(o.getOpenPrice(), o.getStopLoss()) < 0)
    {
      //--- how much do we already profit?
      double pp = o.p(o.getOpenPrice(), o.e());
      //--- if we profit more than those points set in input parameter
      if (pp > o.ap(InpBreakevenPoints))
      {
        //--- if we need to trail step by step
        if (InpBreakevenStep > 0)
        {
          int factor = int(pp / o.ap(InpBreakevenStep));
          if (factor > 0)
          {
            //--- calculate the target price by move stoploss in FAVOR to us
            //--- NOTE that pp can accept points directly in its second parameter
            double sl = o.pp(attr.getOriginalStoploss(), InpBreakevenPoints * factor);
            //--- if target stoploss is better than current one
            //--- (we will profit if we move from current stop loss to `sl`)
            if (o.p(o.getStopLoss(), sl) > 0)
            {
              isSetStopLoss = true;
              //--- if the target make this order breakeven
              if (o.p(o.getOpenPrice(), sl) >= 0)
                //--- we set stop loss to be one point better than open price
                stopLossLevel = o.pp(o.getOpenPrice(), 1);
              else
                stopLossLevel = sl;
            }
          }
        }
        else
        {
          isSetStopLoss = true;
          stopLossLevel = o.pp(o.getOpenPrice(), 1);
        }
      }
    }
  }
  if (isSetStopLoss)
  {
    //--- modify stop loss to *NORMALIZED* price
    if (OrderModify(o.getTicket(), 0, o.n(stopLossLevel), 0, 0, clrNONE))
    {
      //--- notice that we use %s for the price because we need to display the price
      //--- to certain digits based on current order symbol
      PrintFormat(">>> Setting order #%d stoploss to %s", o.getTicket(), o.f(stopLossLevel));
      //--- we modify order state if this modification make the order breakeven
      if (o.p(o.getOpenPrice(), stopLossLevel) >= 0)
        attr.setState(Breakeven);
    }
    else
    {
      Alert(StringFormat(">>> Error setting order #%d stoploss %s", o.getTicket(), o.f(stopLossLevel)));
    }
  }
}
```


## 贡献指引

如果您愿意为这个库做出贡献，我会非常高兴，但是有一些规则您必须遵守。我非常重视代码质量（以及格式）。这绝不是在阻止贡献，相反，我欢迎各个层次的开发者做出贡献.

1. Format the code with MetaEditor (`Ctrl-,`) with **DEFAULT** style. MetaEditor
   is not the best editor or IDE out there, but it is THE IDE for MQL, at least
   for now. And the default style is not good at all (I mean 3 spaces for
   indentation?) but again it is the standard used by most MQL developers. We
   need to follow the community standard to share our knowledge and effort even
   if we do not like it. Unless we can create a better IDE and make the
   community accept it.

2. File encoding: UTF-8. If you use CJK or other non-ASCCI characters, please
   save your file as UTF-8. There are no options in MetaEditor, but you can use
   your favorate editor to do it. Do not save to Unicode in MetaEditor! It will
   save your file in UTF16-LE and Git will think the file is binary.
   
3. Spaces and file ending. Do not leave spaces at after line ending. Leave a
   newline at the file ending.
   
4. Code style. Class members like this: `m_myMember`; method name like this:
   `doThis`; constant and macro definitions like this: `SOME_MACRO`; class name
   like this: `MyClass`; global functions like this: `DoThat`; use `ObjAttr` or
   related macros to define getters and setters. There may be other things to
   notice. Try to keep things consistent as much as possible.
   
5. Copyright. This library is Apache2 licensed. Your contribution will be
   Apache2 licensed, too. But you get your credit for the contribution. If you
   modify some lines of an existing file, you can add your name in the copyright
   line and specify what you have changed and when.

6. I will review your code with you. Prepare for some discussion or questions
   from me. We need to make sure at least the code is decent. I will help you as
   much as I can.
