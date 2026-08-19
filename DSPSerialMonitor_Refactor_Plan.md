# DSP Serial Monitor 通用化与显示布局改造计划

## 1. 任务目标

将当前 `BoostSerialMonitor.m` 改造成一个**通用的 MATLAB DSP/MCU 串口实时波形监视器**。

本次修改只处理 MATLAB 上位机，不修改 DSP/MCU 端代码。

当前设备仍然发送固定 4 通道 CSV 数据，例如：

```text
48.12,75.03,8.42,7.91
```

上位机仍然按“每帧 4 个逗号分隔数值”的方式解析。

本次需要同时完成两类工作：

1. 去除程序中的 Boost 专用命名和默认语义，使程序可以用于 Boost、LLC、逆变器、普通 MCU/DSP 调试等场景。
2. 改造显示层，使用户可以自由设置 Plot 数量，以及每个 Channel 显示在哪个 Plot 中。

---

## 2. 最终定位

程序定位为：

> 一个轻量级、通用的 MATLAB 串口实时波形监视器，用于 DSP、MCU 和数字电源控制系统调试。

不要把程序继续限定为：

```text
Boost
Boost Converter
Boost Controller
```

程序本身不应该假设四个通道一定是：

```text
Vin
Vout
IL
Iout
```

它们只是：

```text
Channel 1
Channel 2
Channel 3
Channel 4
```

用户可以在 GUI 中自行修改名称和单位。

---

## 3. 程序名称

将：

```text
BoostSerialMonitor.m
```

重命名为：

```text
DSPSerialMonitor.m
```

主函数同步改为：

```matlab
function DSPSerialMonitor
```

最终启动方式为：

```matlab
DSPSerialMonitor
```

不要额外创建：

```text
main.m
launcher.m
start.m
runApp.m
```

保持一个明确的 MATLAB 入口。

---

## 4. 必须遵守的约束

1. **不要修改 DSP/MCU 端代码。**
2. **不要修改当前串口数据协议。**
3. 每一帧仍然必须包含 4 个逗号分隔的数值。
4. 仍然使用 LF 作为行终止符。
5. 正常帧与异常帧判断逻辑保持兼容。
6. 不改变数据缓存的基本含义。
7. `state.values` 仍然保存固定 4 个输入通道。
8. 不进行与本任务无关的大规模重构。
9. 不迁移到 App Designer `.mlapp`。
10. 不创建 Windows `.exe`。
11. 保持使用 MATLAB `.m` 文件直接启动 GUI。
12. 不执行任何 Git/GitHub 操作。
13. 不修改远程仓库。
14. 不执行 commit 或 push。
15. 不修改 `AGENTS.md`。
16. 不引入第三方依赖。
17. 保持 MATLAB R2019b 或更新版本可运行。
18. 保留现有 GUI 的总体视觉风格。
19. 保留现有长时间绘图性能优化机制。
20. 只修改完成本任务真正需要修改的代码。

---

## 5. 通用化改造

### 5.1 默认 Channel 名称

将当前带有具体电力电子含义的默认名称：

```text
Vin
Vout
IL
u
```

改为通用名称：

```text
CH1
CH2
CH3
CH4
```

或者：

```text
Channel 1
Channel 2
Channel 3
Channel 4
```

优先使用简洁的：

```text
CH1
CH2
CH3
CH4
```

用户仍然可以在 Channel Settings 中修改为：

```text
Vin
Vout
IL
Duty
```

或：

```text
Vdc
Vac
Iout
Iref
```

程序本身不关心这些名称的物理含义。

---

## 6. 默认 Channel 单位

不要默认假设：

```text
V
V
A
1
```

全部改为无单位：

```text
""
""
""
""
```

用户可自行配置：

```text
V
A
%
Hz
rpm
°C
pu
```

如果单位为空：

```text
ylabel = Channel Name
```

如果单位非空：

```text
ylabel = Channel Name (Unit)
```

---

## 7. 界面中的 Boost 专用文字

搜索整个程序中的：

```text
BOOST
Boost
boost
```

检查每一处是否属于程序名称或通用功能。

例如窗口标题：

```text
BOOST Serial Waveform Monitor
```

改为：

```text
DSP Serial Monitor
```

或者：

```text
DSP Serial Waveform Monitor
```

优先：

```text
DSP Serial Monitor
```

不要修改与功能无关的 MATLAB API 或变量，仅去除用户可见和项目定位中的 Boost 专用语义。

---

## 8. CSV 默认文件名

将：

```text
BoostData_yyyymmdd_HHMMSS.csv
```

改为通用名称：

```text
SerialData_yyyymmdd_HHMMSS.csv
```

或者：

```text
DSPSerialData_yyyymmdd_HHMMSS.csv
```

优先：

```text
SerialData_yyyymmdd_HHMMSS.csv
```

CSV 数据内容和列顺序保持不变：

```text
Time_s
CH1
CH2
CH3
CH4
```

如果用户修改了 Channel Name，则继续使用现有逻辑生成 CSV Variable Name。

---

## 9. MATLAB Preferences 通用化

当前可能存在：

```text
preferencesGroup = 'BoostSerialMonitor'
```

新版本改为：

```text
preferencesGroup = 'DSPSerialMonitor'
```

但必须考虑旧配置迁移。

推荐逻辑：

1. 优先读取新的：

```text
DSPSerialMonitor
```

2. 如果新配置不存在，则尝试读取旧的：

```text
BoostSerialMonitor
```

3. 如果旧配置有效：
   - 将兼容字段迁移到新配置结构。
   - 程序继续正常启动。
4. 如果都不存在：
   - 使用新的通用默认配置。

不要因为程序重命名导致旧 preferences 报错。

如果迁移逻辑会显著增加复杂度，可以采用“读取旧配置但以后保存到新 Group”的方式。

---

# 第二部分：显示布局改造

## 10. Plot 与 Channel 必须解耦

必须明确区分：

```text
Channel
```

和：

```text
Plot
```

Channel 表示设备发送的数据通道。

当前固定为：

```text
4 Channels
```

Plot 表示 GUI 中的显示坐标轴。

允许：

```text
1～4 Plots
```

不要再使用：

```text
1 Channel = 1 Plot
```

这种固定关系。

新的关系应该是：

```text
4 Channels
      ↓
Channel → Plot Mapping
      ↓
1～4 Plots
```

---

## 11. 可配置 Plot 数量

允许用户选择：

```text
1
2
3
4
```

个 Plot。

这里的 Plot 指同一个主 GUI 中的 `uiaxes`。

禁止因为 PlotCount 改变而创建多个独立 MATLAB 窗口。

---

## 12. 推荐 Plot 布局

### 1 Plot

```text
┌────────────────────────────┐
│                            │
│           Plot 1           │
│                            │
└────────────────────────────┘
```

### 2 Plots

优先上下排列：

```text
┌────────────────────────────┐
│           Plot 1           │
├────────────────────────────┤
│           Plot 2           │
└────────────────────────────┘
```

### 3 Plots

如果实现复杂度合理：

```text
┌─────────────┬──────────────┐
│   Plot 1    │    Plot 2    │
├─────────────┴──────────────┤
│           Plot 3           │
└────────────────────────────┘
```

如果 `uigridlayout` 对这种布局实现不够稳定，可以采用：

```text
3 × 1
```

上下排列。

优先保证：

```text
简单
稳定
可维护
```

不要为了布局美观写大量特殊代码。

### 4 Plots

使用：

```text
2 × 2
```

与当前布局接近。

---

## 13. Channel → Plot 映射

每个 Channel 增加一个：

```text
Plot
```

配置项。

例如：

```text
CH1 → Plot 1
CH2 → Plot 1
CH3 → Plot 2
CH4 → Plot 2
```

结果：

```text
Plot 1:
CH1
CH2

Plot 2:
CH3
CH4
```

必须支持：

```text
1 Channel / Plot
2 Channels / Plot
3 Channels / Plot
4 Channels / Plot
```

允许 Plot 中没有任何 Channel。

一个 Channel 第一版只允许属于一个 Plot。

本次不要实现：

```text
CH1 同时出现在 Plot 1 和 Plot 2
```

---

## 14. Channel Visible

每个 Channel 增加：

```text
Visible
```

属性。

例如：

```text
CH1 = true
CH2 = true
CH3 = true
CH4 = false
```

当：

```text
Visible = false
```

时：

- 设备数据仍然正常接收。
- 数据仍然进入 `state.values`。
- 仍然计入有效帧。
- CSV 仍然保存该 Channel。
- 只是 GUI 中不绘制该 Channel。

Visible 只属于显示层。

---

## 15. Channel Settings 窗口

保留当前已有配置，并扩展为：

| 项目 | 含义 |
|---|---|
| Name | Channel 名称 |
| Unit | Channel 单位 |
| Visible | 是否显示 |
| Plot | 显示在哪个 Plot |
| Expand Y | 是否允许超限扩展 |
| Y Min | 基础最小显示范围 |
| Y Max | 基础最大显示范围 |

GUI 中文显示可以使用：

```text
名称
单位
显示
图号
超限扩展
Y 最小值
Y 最大值
```

---

## 16. Plot Count 设置位置

在主界面的：

```text
显示设置
```

区域中增加：

```text
图表数量
```

推荐使用：

```matlab
uidropdown
```

选项：

```text
1
2
3
4
```

用户修改后，可以选择：

### 方案 A

立即应用布局。

或者：

### 方案 B

与 Channel Settings 一起点击“应用”后生效。

优先采用更简单、更稳定的实现。

如果立即应用会增加较多状态同步问题，则统一在设置窗口点击“应用”时完成。

---

## 17. Plot Index 合法性

必须满足：

```text
1 <= plotIndex <= plotCount
```

当 PlotCount 变小时自动修正 Channel 的 PlotIndex。

例如：

```text
原：
CH4 → Plot 4

修改：
PlotCount = 2
```

自动变为：

```text
CH4 → Plot 2
```

推荐：

```text
plotIndex = min(plotIndex, plotCount)
```

不能因为 PlotCount 改变导致程序报错。

---

# 第三部分：绘图实现

## 18. Handles 数据结构

当前逻辑如果是：

```text
axesHandles(channelIndex)
lineHandles(channelIndex)
```

需要改造为：

```text
axesHandles(plotIndex)
lineHandles(channelIndex)
```

也就是说：

```text
axesHandles
```

数量由 PlotCount 决定。

而：

```text
lineHandles
```

仍然固定有 4 个，对应 4 个输入 Channel。

---

## 19. Line 所属 axes

每次布局重建时：

```text
Channel 1
```

根据：

```text
channelSettings.plotIndex(1)
```

找到对应 axes。

例如：

```text
plotIndex = 2
```

则：

```text
CH1 line → axesHandles(2)
```

多个 line 可以同时属于同一个 axes。

---

## 20. 不要在串口 callback 中重建布局

这是必须遵守的性能要求。

禁止在每次收到数据后：

```text
delete axes
delete lines
create axes
create lines
```

布局重建只允许发生在：

```text
程序启动
用户修改 PlotCount
用户修改 Channel → Plot 映射
用户应用 Channel Settings
```

普通串口接收时只允许更新：

```text
XData
YData
Visible
XLim
YLim
```

---

## 21. Plot Layout 重建函数

建议新增一个职责清晰的内部函数，例如：

```matlab
rebuildPlotLayout()
```

它只负责显示结构。

主要职责：

1. 根据 PlotCount 创建 axes。
2. 设置 Layout Row / Column。
3. 根据 Channel → Plot 映射创建 4 个 line。
4. 设置 Channel 颜色。
5. 更新 Plot Title。
6. 更新 YLabel。
7. 更新 Legend。
8. 应用当前 YLim。
9. 如果已有缓存数据，则重新调用 `updatePlots()` 显示已有数据。

不要把串口连接、读取或 CSV 保存逻辑放进这个函数。

---

## 22. Channel 颜色

继续保留当前四种 Channel 颜色。

颜色属于：

```text
Channel
```

而不是：

```text
Plot
```

例如：

```text
CH1 → 蓝色
CH2 → 橙色
CH3 → 绿色
CH4 → 紫色
```

不论 CH1 被分配到 Plot 1、2、3 或 4：

```text
CH1 始终使用同一种颜色
```

---

## 23. Legend

当一个 Plot 中：

```text
可见 Channel 数量 >= 2
```

显示 Legend。

Legend 名称使用用户配置的 Channel Name。

例如：

```text
Plot 1
CH1 = Vin
CH2 = Vout
```

Legend 显示：

```text
Vin
Vout
```

当一个 Plot 中只有一条可见曲线时，可以不显示 Legend。

当一个 Plot 中没有可见 Channel 时，不显示 Legend。

---

## 24. Plot Title

根据当前 Plot 中可见 Channel 自动生成。

例如：

```text
Vin / Vout
```

或者：

```text
IL / Duty
```

如果当前 Plot 没有 Channel：

```text
Plot 2
```

如果标题过长，应保持可读性，不要生成过度复杂的标题。

---

## 25. X Label

所有 Plot 保持：

```text
Time (s)
```

不要修改。

---

## 26. Y Label

如果同一个 Plot 中所有可见 Channel 的 Unit 相同，并且 Unit 非空：

```text
Amplitude (V)
```

或者直接：

```text
V
```

优先简洁。

如果多个 Channel Unit 不同：

```text
Value
```

如果 Unit 全部为空：

```text
Value
```

本次不实现多个 YLabel。

---

## 27. 本次不实现双 Y 轴

明确禁止本次加入：

```matlab
yyaxis left
yyaxis right
```

即使出现：

```text
Current = 8 A
Duty = 0.4
```

同图显示。

原因：

- 会增加 Plot 与 Channel 的状态管理复杂度。
- 会影响现有 YLim 自动扩展。
- 当前目标是先完成稳定的多曲线显示。

用户需要自行合理安排同一 Plot 中的 Channel。

---

# 第四部分：Y 轴逻辑

## 28. YLim 从 Channel 适配到 Plot

现有配置仍然可以保留每个 Channel 的：

```text
YMin
YMax
ExpandY
```

但最终 axes 的 YLim 属于 Plot。

因此一个 Plot 中有多个可见 Channel 时：

```text
Plot YMin = min(所有可见 Channel 的 YMin)

Plot YMax = max(所有可见 Channel 的 YMax)
```

例如：

```text
CH1: 0 ~ 60
CH2: 0 ~ 100
```

同在 Plot 1：

```text
Plot 1 YLim = [0 100]
```

---

## 29. Expand Y

如果一个 Plot 中任意可见 Channel：

```text
ExpandY = true
```

并且该 Channel 当前数据超过 Plot YLim：

允许该 Plot 的 Y 轴扩大。

扩大以后不要在每一帧自动缩小。

保持现有“只扩大，不自动缩回”的设计。

---

## 30. Reset Y Axis

“重置 Y 轴”功能必须继续存在。

新的行为：

1. 遍历所有 Plot。
2. 根据该 Plot 内可见 Channel 的基础 YMin/YMax 计算基础范围。
3. 检查当前时间窗口内可见数据。
4. 根据 ExpandY 规则决定是否扩大。
5. 更新 axes。

---

# 第五部分：updatePlots

## 31. 保留现有数据窗口逻辑

继续使用：

```text
windowField.Value
```

决定显示时间窗口。

不要修改当前时间数据的来源。

本次不增加 DSP Timestamp。

---

## 32. 保留绘图降采样

继续保留：

```matlab
maxPlotSamples = 2000;
```

不要因为多曲线功能移除。

---

## 33. updatePlots() 推荐流程

新的 `updatePlots()` 应：

1. 判断是否有缓存数据。
2. 获取：

```text
visibleStart
visibleEnd
```

3. 计算可见范围内逻辑索引。
4. 根据 `maxPlotSamples` 抽点。
5. 只生成一次：

```matlab
shownTime
shownValues
```

6. 遍历 4 个 Channel。
7. 对每个 Channel：
   - 检查 Visible。
   - 找到 PlotIndex。
   - 更新对应 line 的 `XData`。
   - 更新对应 line 的 `YData`。
8. 遍历现有 Plot 更新 `XLim`。
9. 最后只执行一次：

```matlab
drawnow limitrate nocallbacks
```

不要针对每个 Channel 单独 `drawnow`。

---

# 第六部分：性能要求

## 34. 必须保留以下机制

不要破坏：

```matlab
plotPeriod = 0.05;
counterPeriod = 0.2;
maxPlotSamples = 2000;
maxStoredSamples = 360000;
```

这些机制用于：

- 限制 GUI 刷新频率。
- 避免长时间运行时绘图点数过多。
- 控制内存占用。
- 保持串口接收与 GUI 绘图解耦。

---

## 35. 串口 callback

不要进行无关重构。

当前接收逻辑仍然保持：

```text
readline
split by comma
str2double
numel == 4
finite check
store
counter
plot refresh
```

本次不要：

- 改二进制协议。
- 改成其他分隔符。
- 增加 CRC。
- 增加 Frame ID。
- 增加 DSP Timestamp。
- 增加动态通道数量。

---

# 第七部分：配置持久化

## 36. 新配置结构

新的显示配置至少应包含：

```text
names
units
visible
plotIndex
expandY
yLimits
plotCount
```

推荐默认值：

```text
names =
CH1
CH2
CH3
CH4

units =
""
""
""
""

visible =
true true true true

plotIndex =
1 2 3 4

plotCount =
4
```

---

## 37. 旧 preferences 兼容

需要兼容当前 BoostSerialMonitor 已保存的旧配置。

旧配置可能只有：

```text
names
units
expandY
yLimits
```

如果缺少：

```text
visible
plotIndex
plotCount
```

自动补：

```text
visible = [true true true true]

plotIndex = [1 2 3 4]

plotCount = 4
```

不允许因为旧配置字段缺失导致程序启动失败。

---

# 第八部分：现有功能必须保持

## 38. Refresh Ports

继续正常工作。

不改变：

```text
serialportlist("available")
serialportlist("all")
```

相关逻辑。

---

## 39. Connect / Disconnect

继续正常工作。

不改变：

```text
8 Data Bits
1 Stop Bit
No Parity
No Flow Control
LF Terminator
```

等基本配置。

---

## 40. Pause Display

继续保持：

```text
暂停显示 != 暂停采集
```

暂停时：

- 数据继续接收。
- 缓存继续更新。
- 不刷新 Plot。

恢复时：

- 根据当前 Plot 配置重新显示最新数据。

---

## 41. Clear

Clear 时：

- 清空采样数据。
- 清空有效帧/异常帧计数。
- 清空所有 line。
- 不修改 Channel Name。
- 不修改 Unit。
- 不修改 Visible。
- 不修改 PlotIndex。
- 不修改 PlotCount。

---

## 42. Save CSV

显示布局不得影响 CSV。

无论：

```text
Channel Visible = false
```

还是：

```text
CH1 和 CH2 在同一个 Plot
```

CSV 都继续保存全部 4 Channel。

列顺序固定为：

```text
Time
CH1
CH2
CH3
CH4
```

名称根据当前用户设置生成合法 MATLAB Variable Name。

---

## 43. Window (s)

继续工作。

PlotCount 和多曲线显示不得影响：

```text
Window (s)
```

功能。

---

## 44. 串口诊断

保留当前：

```text
全部端口
可用端口
MATLAB error identifier
原始错误
```

等连接失败诊断信息。

不要因为通用化删掉有价值的错误提示。

---

# 第九部分：推荐实施顺序

## Step 1：阅读代码

开始修改前：

1. 阅读 `AGENTS.md`。
2. 阅读完整 `BoostSerialMonitor.m`。
3. 理解：
   - 串口接收。
   - 数据缓存。
   - 绘图。
   - Channel Settings。
   - YLim。
   - Preferences。
   - CSV 保存。
4. 不要先写代码。

---

## Step 2：程序通用化

完成：

```text
BoostSerialMonitor.m
→ DSPSerialMonitor.m
```

修改：

```matlab
function BoostSerialMonitor
```

为：

```matlab
function DSPSerialMonitor
```

修改：

```text
BOOST Serial Waveform Monitor
```

为：

```text
DSP Serial Monitor
```

修改默认 Channel：

```text
CH1
CH2
CH3
CH4
```

修改默认 Unit：

```text
空
```

修改 CSV 默认文件名。

暂时不要改串口逻辑。

---

## Step 3：扩展配置结构

增加：

```text
visible
plotIndex
plotCount
```

同时做好旧 preferences 兼容。

---

## Step 4：改造 Channel Settings

增加：

```text
显示
图号
Plot 数量
```

增加数据校验。

---

## Step 5：实现 Plot Layout Manager

增加类似：

```matlab
rebuildPlotLayout()
```

的内部函数。

只处理 GUI Plot 和 Line。

---

## Step 6：改造 updatePlots()

让 4 个 Channel 根据：

```text
Visible
PlotIndex
```

更新到目标 Plot。

---

## Step 7：适配 Legend / Title / YLabel

完成多曲线 UI 信息。

---

## Step 8：适配 Y 轴

实现：

```text
多个 Channel → 一个 Plot YLim
```

逻辑。

---

## Step 9：回归检查

检查所有原有功能没有被破坏。

---

# 第十部分：测试场景

## 45. 默认模式

```text
PlotCount = 4

CH1 → Plot 1
CH2 → Plot 2
CH3 → Plot 3
CH4 → Plot 4
```

应与旧版本显示结构基本一致。

---

## 46. 单 Plot 模式

```text
PlotCount = 1

CH1 → Plot 1
CH2 → Plot 1
CH3 → Plot 1
CH4 → Plot 1
```

预期：

```text
1 Plot
4 Lines
Legend 显示 4 个 Channel
```

---

## 47. 双 Plot 模式

```text
PlotCount = 2

CH1 → Plot 1
CH2 → Plot 1
CH3 → Plot 2
CH4 → Plot 2
```

预期：

```text
Plot 1 = 2 Lines
Plot 2 = 2 Lines
```

---

## 48. 三 Plot 模式

```text
PlotCount = 3

CH1 → Plot 1
CH2 → Plot 2
CH3 → Plot 3
CH4 → Plot 3
```

预期：

```text
Plot 1 = 1 Line
Plot 2 = 1 Line
Plot 3 = 2 Lines
```

---

## 49. Visible

设置：

```text
CH4 Visible = false
```

预期：

- CH4 不绘制。
- CH4 继续接收。
- CH4 继续保存 CSV。

---

## 50. Channel Name

把：

```text
CH1
CH2
CH3
CH4
```

修改为：

```text
Vin
Vout
IL
Duty
```

预期：

- Title 更新。
- Legend 更新。
- CSV Variable Name 更新。
- 串口协议不变。

---

## 51. PlotCount 减小

先：

```text
PlotCount = 4
CH4 → Plot 4
```

再改：

```text
PlotCount = 2
```

预期：

```text
CH4 自动修正到 Plot 2
```

程序不报错。

---

## 52. Restart

修改配置后：

1. 关闭程序。
2. 再次运行：

```matlab
DSPSerialMonitor
```

预期：

- PlotCount 恢复。
- Channel Name 恢复。
- Unit 恢复。
- Visible 恢复。
- PlotIndex 恢复。
- Y 轴设置恢复。

---

# 第十一部分：不允许出现的回归问题

必须确认：

- MATLAB 可以正常运行 `DSPSerialMonitor`。
- GUI 正常创建。
- 串口列表正常刷新。
- 串口正常连接。
- 串口正常断开。
- 115200 baud 正常。
- 固定 4 通道 CSV 正常。
- 异常帧仍然能被识别。
- 有效帧计数正常。
- 异常帧计数正常。
- Pause 正常。
- Clear 正常。
- Save CSV 正常。
- Reset Y Axis 正常。
- Window(s) 正常。
- 长时间缓存逻辑没有被删除。
- `maxPlotSamples` 降采样仍然存在。
- GUI Close 时 callback 正确关闭。
- 旧 preferences 不会导致程序启动失败。

---

# 第十二部分：错误处理

必须处理：

```text
PlotCount 非法
PlotIndex 非法
Channel Name 为空
YMin >= YMax
Preferences 数据损坏
Plot 没有任何 Channel
Visible 全部为 false
采集中修改布局
```

如果用户输入无效：

- 使用 `uialert` 提示。
- 不要让 GUI 崩溃。
- 不要破坏串口连接。
- 尽量恢复最近一次有效配置。

---

# 第十三部分：代码风格

1. 保持现有代码风格。
2. MATLAB GUI 可以继续使用中文。
3. Plot 的 xlabel 使用英文。
4. Channel Name 根据用户设置。
5. 不做无关变量重命名。
6. 不大规模改写串口部分。
7. 新增函数职责单一。
8. 对 Plot Mapping 增加必要注释。
9. 避免复制 4 份相似逻辑。
10. 不添加不需要的新文件。
11. 不添加第三方库。

---

# 第十四部分：Codex 工作规则

Codex 开始前必须：

```text
1. 阅读 AGENTS.md
2. 阅读本 Plan
3. 阅读完整现有 MATLAB 文件
4. 先理解后修改
```

修改过程中：

- 小步修改。
- 不做无关重构。
- 不修改 DSP。
- 不执行 Git。
- 不执行 GitHub 操作。
- 不修改本 Plan。
- 不修改 AGENTS.md。

如果可以调用 MATLAB：

- 执行必要语法检查。
- 能自动测试的部分尽量测试。

如果无法调用 MATLAB GUI：

- 不允许声称 GUI 已经实际验证。
- 做静态检查。
- 在最终结果中明确列出需要用户人工验证的项目。

---

# 第十五部分：完成后的 Codex 汇报格式

完成后只需要汇报以下内容。

## 修改内容

例如：

```text
- 程序重命名为 DSPSerialMonitor
- 去除 Boost 专用默认名称
- 增加 PlotCount
- 增加 Channel Visible
- 增加 Channel → Plot Mapping
- 支持一个 Plot 多条曲线
- 增加 Legend
- 适配 Y 轴
- 增加旧 Preferences 兼容
```

## 修改文件

明确列出实际修改文件。

预期：

```text
BoostSerialMonitor.m → DSPSerialMonitor.m
```

如果新增其他文件，必须说明为什么。

## 测试

区分：

```text
已实际验证
```

和：

```text
需要人工验证
```

不要伪造测试结果。

## 人工验证

至少建议用户测试：

```text
1 Plot / 4 Channels
2 Plots / 2+2
3 Plots / 1+1+2
4 Plots / 1+1+1+1
Visible
Channel Rename
Pause
Clear
Save CSV
Restart
```

---

# 第十六部分：最终验收标准

只有同时满足以下条件才算完成：

- 程序不再以 Boost 为项目定位。
- MATLAB 文件名为 `DSPSerialMonitor.m`。
- 启动命令为 `DSPSerialMonitor`。
- DSP/MCU 代码不需要修改。
- 串口仍接收固定 4 通道 CSV。
- 默认 Channel 为通用 CH1～CH4。
- 用户可以修改 Channel 名称和单位。
- 可以选择 1～4 个 Plot。
- 任意 Channel 可以分配到任意现有 Plot。
- 同一个 Plot 可以显示多个 Channel。
- Channel 可以单独隐藏。
- 多曲线 Plot 可以显示 Legend。
- 默认 4 Plot 模式与旧程序使用习惯兼容。
- CSV 与 GUI 显示布局解耦。
- 串口接收逻辑没有被无关重构。
- 长时间绘图性能机制仍然存在。
- 配置可以持久化。
- 旧 preferences 有兼容处理。
- 没有执行 Git/GitHub 操作。

---

# 第十七部分：本次明确不做

本次不要实现：

```text
动态串口通道数量
修改 DSP 协议
Frame ID
DSP Timestamp
CRC
二进制串口协议
双 Y 轴
Trigger
Cursor
FFT
数据滤波
Replay Mode
Demo Mode
App Designer
.mlapp
.exe
Git init
Git commit
Git push
GitHub 仓库
```

这些全部留到未来版本。

---

# 最终目标

本次改造最终应得到：

> `DSPSerialMonitor.m`：一个与具体 Boost 项目无关的、可直接通过 MATLAB 启动的通用 4 通道 DSP/MCU 串口实时波形监视器。它保持现有串口协议兼容，同时支持 1～4 个 Plot、Channel 显示/隐藏，以及任意 Channel → Plot 映射和同 Plot 多曲线显示。
