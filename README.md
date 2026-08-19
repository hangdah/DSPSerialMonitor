# DSP Serial Monitor

一个轻量级的 MATLAB 串口实时波形监视器，用于 DSP、MCU 和数字电源控制系统调试。

程序直接通过 MATLAB `.m` 文件启动，不依赖 App Designer、第三方库或额外启动脚本。当前版本默认接收 4 通道 CSV 数据，通道数可配置为 1～16，并支持将任意 Channel 映射到 1～4 个 Plot 中显示。

## 功能特性

- 1～16 通道串口数据接收与实时波形显示，默认 4 通道
- 支持 1～4 个 Plot，可在采集过程中调整布局
- 支持多个 Channel 显示在同一个 Plot
- 每个 Channel 使用固定的独立颜色，可设置名称、单位、显示状态和目标 Plot
- 多曲线 Plot 自动生成标题和 Legend
- 支持基础 Y 轴范围、超限扩展和手动重置
- 暂停显示时继续接收并缓存串口数据
- 有效帧、异常帧和缓存点数统计
- CSV 导出始终包含当前配置的全部输入通道
- 有界环形缓存和绘图降采样，适合长时间采集
- 显示配置通过 MATLAB Preferences 自动保存
- 兼容旧版 `BoostSerialMonitor` 显示配置
- 串口连接失败时显示端口状态和 MATLAB 原始错误信息

## 环境要求

- MATLAB R2019b 或更高版本
- 支持 MATLAB `serialport` 接口的串口设备和驱动
- 无第三方 MATLAB 依赖

当前界面和串口诊断信息主要按 Windows 使用环境设计，默认串口为 `COM10`，可在 GUI 中选择其他已检测到的端口。

## 快速开始

1. 下载或克隆本仓库。
2. 在 MATLAB 中将当前文件夹切换到项目目录，或将项目目录加入 MATLAB Path。
3. 在 MATLAB Command Window 中运行：

```matlab
DSPSerialMonitor
```

4. 在界面中选择串口和波特率，点击“连接”。

默认波特率为 `115200`。

## 串口协议

每一帧为一行文本，必须包含与当前“通道数”设置完全一致的逗号分隔有限数值：

```text
value1,value2,...,valueN<LF>
```

示例：

```text
48.12,75.03,8.42,7.91
```

串口参数：

| 参数 | 设置 |
|---|---|
| Data bits | 8 |
| Stop bits | 1 |
| Parity | None |
| Flow control | None |
| Line terminator | LF |
| Default baud rate | 115200 |

字段数量与当前通道数不一致、包含非数值字段或包含 `NaN`/`Inf` 的数据行会被计为异常帧，但不会停止后续采集。

设备端发送格式可以参考：

```c
printf("%.3f,%.3f,%.3f,%.3f\n", ch1, ch2, ch3, ch4);
```

## 界面说明

### 采集控制

| 控件 | 功能 |
|---|---|
| 刷新串口 | 重新检测系统中的串口 |
| 连接 / 断开 | 建立或关闭串口连接 |
| 暂停显示 / 继续显示 | 暂停或恢复绘图；暂停期间仍继续采集数据 |
| 重置 Y 轴 | 按基础范围和当前时间窗口内的数据重新计算 Y 轴 |
| 清屏 | 清空采样缓存和统计，不改变显示配置 |
| 保存 CSV | 将当前缓存中的全部活动通道数据导出 |

### 显示设置

- `窗口 (s)`：设置波形显示的时间窗口，范围为 0.5～3600 秒。
- `图表数`：选择主界面显示 1～4 个 Plot。
- `通道设置`：配置各 Channel 的显示属性和 Y 轴参数。

Channel Settings 包含：

| 设置 | 说明 |
|---|---|
| 通道数 | 设置设备每帧发送的数据数量，范围为 1～16 |
| 名称 | Plot 标题、Legend 和 CSV 列名使用的 Channel 名称 |
| 单位 | 同一 Plot 内可见 Channel 单位相同时用于 YLabel |
| 显示 | 仅控制 GUI 是否绘制，不影响接收、缓存和 CSV 导出 |
| 图号 | 指定 Channel 显示到哪个 Plot |
| 超限扩展 | 数据超出当前范围时是否允许对应 Plot 扩大 Y 轴 |
| Y 最小值 / Y 最大值 | Channel 的基础显示范围 |

当图表数量减小时，超出范围的 Channel 图号会自动修正到最后一个可用 Plot。

修改通道数前必须断开串口连接。如果当前缓存中已有采样数据，还需要先保存所需数据并点击“清屏”；程序不会自动丢弃已有数据。减少通道数时，暂时停用通道的名称、单位、Plot 映射和 Y 轴配置仍会保留。

## 布局示例

单 Plot 显示全部 Channel：

```text
PlotCount = 1
CH1, CH2, CH3, CH4 -> Plot 1
```

双 Plot 分组显示：

```text
CH1, CH2 -> Plot 1
CH3, CH4 -> Plot 2
```

默认布局：

```text
PlotCount = 4
CH1 -> Plot 1
CH2 -> Plot 2
CH3 -> Plot 3
CH4 -> Plot 4
```

Channel 颜色与 Channel 本身绑定，改变目标 Plot 不会改变曲线颜色。

## 数据缓存与绘图

- `state.values` 保存当前配置的 1～16 个输入通道。
- 最多缓存 `360000` 个采样点，缓存满后按时间顺序覆盖最旧数据。
- 绘图刷新周期不高于约 20 次/秒。
- 每次绘图最多显示 `2000` 个抽样点，以限制长时间窗口的图形负载。
- Channel 隐藏后仍会继续接收、缓存并导出。
- Plot 数量和 Channel 映射只影响显示层，不改变串口协议或 CSV 通道顺序。

## CSV 导出

默认文件名格式：

```text
SerialData_yyyymmdd_HHMMSS.csv
```

第一列为 `Time_s`，后续列按 CH1～CHN 的活动输入顺序保存。用户修改 Channel 名称或单位后，程序会将其转换为合法且唯一的 CSV 列名。

## 配置保存

通道数、Channel 名称、单位、显示状态、Plot 映射、Plot 数量和 Y 轴设置会保存到 MATLAB Preferences：

```text
DSPSerialMonitor / ChannelDisplaySettings
```

如果新配置不存在，程序会尝试读取旧版：

```text
BoostSerialMonitor / ChannelDisplaySettings
```

缺失或损坏的配置字段会使用安全默认值，避免影响应用启动。

## 项目结构

```text
DSPSerialMonitor.m                 主程序
DSPSerialMonitor_Refactor_Plan.md  通用化与显示布局改造计划
AGENTS.md                          项目开发约束
README.md                          项目说明
```

## 当前限制

- 输入通道数量可配置为 1～16，但采集期间不能动态改变。
- 仅支持逗号分隔的文本协议和 LF 行终止符。
- 不支持二进制协议、CRC、设备时间戳或按每帧字段数自动改变通道数量。
- 一个 Channel 只能分配到一个 Plot。
- 不支持双 Y 轴、触发、FFT、回放和数据滤波。
- 本工具只负责串口数据监视，不会修改 DSP/MCU 控制参数或硬件配置。

## 常见问题

### MATLAB 找不到 `DSPSerialMonitor`

确认 MATLAB Current Folder 是本项目目录，或先执行：

```matlab
addpath('项目所在目录')
DSPSerialMonitor
```

### 串口存在但无法连接

确认串口未被串口助手、IDE 或其他 MATLAB 会话占用，然后点击“刷新串口”。连接失败对话框会同时显示全部端口、可用端口、MATLAB 错误标识和驱动返回的原始错误。

### 点击“暂停显示”后是否还会保存数据

会。暂停只停止图形刷新，串口读取、缓存和帧计数仍然继续进行。
