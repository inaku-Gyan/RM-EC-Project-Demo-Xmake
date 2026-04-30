# EC-Project-Demo

STM32F407 嵌入式机器人下位机。通过 USB CDC 与 Linux 上位机通信，控制电机等执行器。

**工具链**：arm-none-eabi-gcc · **构建**：Xmake · **语言**：C++20 / C11 · **RTOS**：FreeRTOS (CMSIS-RTOS v2) · **HAL**：STM32 HAL

---

## 目录结构

```
EC-Project-Demo/
├── xmake.lua                  # 根构建入口
├── xmake/
│   ├── toolchain.lua          # ARM GCC 工具链定义
│   └── cubemx.lua             # CubeMX 源文件/include 路径收集
├── .clang-format
├── .clang-tidy
├── bsp/
│   ├── interface.h            # CubeMX → C++ 的唯一接口契约（C 兼容）
│   └── CubeMX/                # CubeMX 生成，视为只读
│       ├── CubeMX.ioc         # 外设配置唯一入口，重新生成从这里操作
│       ├── Inc/ Src/
│       ├── Drivers/
│       └── Middlewares/
├── src/                       # 本项目应用代码
│   ├── entry.cpp              # user_init()：创建所有任务，连接各模块
│   ├── driver/                # 板载设备驱动（与本项目硬件强绑定）
│   │   ├── dji_motor.hpp/.cpp
│   │   └── bmi088.hpp/.cpp
│   ├── comm/                  # USB CDC 协议层
│   │   ├── usb_comm.hpp/.cpp  # 双缓冲收发、信号量管理
│   │   └── protocol.hpp       # 消息类型定义（packed struct + COBS）
│   └── tasks/                 # FreeRTOS 任务入口（自由函数）
│       ├── control_task.cpp
│       ├── comm_task.cpp
│       └── monitor_task.cpp
└── lib/
    └── ec-lib/                # 跨项目共享中间件（Git submodule）
        ├── rtos/              # FreeRTOS 类型安全薄封装
        ├── algo/              # PID、滤波器模板
        └── proto/             # COBS、CRC
```

---

## 代码来源与管理

| 目录              | 来源         | 修改方式                                            |
| ----------------- | ------------ | --------------------------------------------------- |
| `bsp/CubeMX/`     | CubeMX 生成  | 只改 USER CODE 段；重新配置外设时用 CubeMX 重新生成 |
| `bsp/interface.h` | 手写         | 声明所有 CubeMX 可调用的 C++ 函数                   |
| `src/`            | 手写         | 自由修改                                            |
| `lib/ec-lib/`     | 自研共享库   | 在 submodule 的独立 repo 里修改，本项目只消费       |
| ETL 等第三方      | xmake 包管理 | xmake lock 文件锁定版本                             |

---

## CubeMX 集成策略

**原则：USER CODE 段只写一行调用，实现全部在 C++ 侧。**

CubeMX 文件中有且仅有以下几处修改：

```c
// freertos.c - StartDefaultTask
MX_USB_DEVICE_Init();     // 已有
#include "bsp/interface.h"
user_init();              // 新增：创建所有任务后返回，此任务继续空跑

// usbd_cdc_if.c - CDC_Init_FS USER CODE BEGIN 3
#include "bsp/interface.h"
usb_cdc_init_rx();
return USBD_OK;

// usbd_cdc_if.c - CDC_Receive_FS USER CODE BEGIN 6
#include "bsp/interface.h"
usb_cdc_rx_handler(Buf, *Len);
return USBD_OK;

// usbd_cdc_if.c - CDC_TransmitCplt_FS USER CODE BEGIN 14
#include "bsp/interface.h"
usb_cdc_tx_cplt();

// main.c - Error_Handler USER CODE BEGIN Error_Handler_Debug
#include "bsp/interface.h"
user_error_handler();

// main.c - assert_failed USER CODE BEGIN 6
#include "bsp/interface.h"
user_assert_failed(file, line);
```

`bsp/interface.h` 是 CubeMX 与 C++ 层之间的**唯一耦合点**，集中声明所有接口：

```c
// bsp/interface.h —— C 兼容，不含任何 C++ 语法
#pragma once
#include <stdint.h>

void user_init(void);
void user_error_handler(void);
void user_assert_failed(uint8_t* file, uint32_t line);

void usb_cdc_init_rx(void);
void usb_cdc_rx_handler(uint8_t* buf, uint32_t len);
void usb_cdc_tx_cplt(void);
```

**HAL RegisterCallback** 不在 MspInit 的 USER CODE 里注册，而是在 `user_init()` 中统一注册，彻底避免动 `stm32f4xx_hal_msp.c`。

---

## 架构分层

```
src/tasks/      应用层：任务逻辑、状态机（与本机器人强绑定）
src/comm/       通信层：USB CDC 双缓冲、协议编解码
src/driver/     驱动层：具体设备驱动（DJI 电机、IMU 等）
lib/ec-lib/     共享层：RTOS 封装、算法模板、协议工具（跨项目）
bsp/CubeMX/     BSP 层：外设初始化、HAL、FreeRTOS、USB 栈（只读）
```

驱动层和共享层可**直接调用 HAL 函数**，无需再封装一层。零成本的 C++ 封装（模板、inline）值得做；引入间接跳转的封装（虚函数、std::function）不做。

---

## FreeRTOS 任务模式

**任务 = 自由函数 + 文件作用域静态状态**，不用 class 包装。

```cpp
// src/tasks/control_task.cpp
namespace {
    DjiMotor g_motors[4];
    TickType_t g_last_wake;
}

void control_task(void*) {
    g_last_wake = xTaskGetTickCount();
    for (;;) {
        for (auto& m : g_motors) m.update();
        vTaskDelayUntil(&g_last_wake, pdMS_TO_TICKS(1));
    }
}
```

任务在 `entry.cpp` 的 `user_init()` 里用 `xTaskCreateStatic` 创建，全部静态分配（`StaticTask_t` + 静态栈数组）。

---

## USB CDC 双缓冲

USB FS 每包最大 64 字节。使用 ping-pong 双缓冲：收到数据后立即切换端点缓冲区并重新 arm，再处理上一包数据，消除单缓冲的 NAK 窗口。

- RX：2×64 字节 ping-pong buffer，在 `usb_cdc_rx_handler`（中断上下文）里切换，数据通过 `xQueueSendFromISR` 入队。
- TX：`src/comm/usb_comm.cpp` 自持静态 tx_buf，用二值信号量等待 `TransmitCplt` 后才允许下次发送。发送接口对上层是同步的。
- `UserRxBufferFS` / `UserTxBufferFS`（CubeMX 生成的 2048 字节缓冲区）弃用不使用。

---

## 构建系统

CubeMX 代码编译为独立静态库 `cubemx`，使用 C11、关闭所有 warning，include 路径通过 `{public = true}` 透传给主目标。主目标 `ec_demo` 使用 C++20，应用完整 warning 规则。

```lua
-- 主目标关键 flags
add_cxxflags("-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics")
add_cxxflags("-Wall", "-Wextra", "-Werror")
add_cxflags("-mcpu=cortex-m4", "-mfpu=fpv4-sp-d16", "-mfloat-abi=hard", "-mthumb")
-- Release 模式开启 LTO
```

---

## 代码规范（fmt / lint）

**作用范围：`src/` 和 `lib/ec-lib/`，`bsp/` 和第三方库完全排除。**

`.clang-format`：基于 Google style，ColumnLimit 100，IndentWidth 4，PointerAlignment Left。

`.clang-tidy` 启用：`modernize-*`、`bugprone-*`、`readability-*`、`performance-*`、`cppcoreguidelines-pro-type-cstyle-cast`、`cppcoreguidelines-pro-type-vararg`。

`.clang-tidy` 禁用：`fuchsia-*`、`abseil-*`、`readability-magic-numbers`、`cppcoreguidelines-avoid-magic-numbers`（寄存器操作大量使用字面量）、`cppcoreguidelines-pro-bounds-pointer-arithmetic`。

---

## 禁用的 C++ 特性

以下特性在嵌入式环境不适用，通过**编译器 flag 强制禁用**：

| 特性                          | 禁用方式                  |
| ----------------------------- | ------------------------- |
| 异常（`try/catch/throw`）     | `-fno-exceptions`         |
| RTTI（`dynamic_cast/typeid`） | `-fno-rtti`               |
| 线程安全静态初始化            | `-fno-threadsafe-statics` |

以下特性通过**设计约束**避免（不依赖 linter 强制，code review 把关）：

- **虚函数**：有间接跳转开销，热路径不可内联；同一逻辑多实例时用 CRTP 代替
- **`std::function`**：内部可能堆分配，用 `etl::delegate` 代替
- **`std::vector/string`**：堆分配，用 `etl::vector/string` 代替
- **`new/delete`**：堆碎片，用静态/栈分配代替
- **`std::thread/mutex`**：对接 OS 线程而非 FreeRTOS，直接用 FreeRTOS API
- **全局对象访问硬件**：HAL 在 `main()` 里初始化，全局构造函数执行时 HAL 尚未就绪；硬件相关对象只在 `user_init()` 内初始化

推荐使用的零开销 C++ 特性：`std::array`、`std::span`、`std::optional`、`std::atomic`、`std::byte`、`std::bit_cast`、`constexpr/consteval`、Concepts、模板、结构化绑定、`if constexpr`。

---

## ec-lib 边界

**放入 ec-lib**（与具体机器人无关，可跨项目复用）：

- `rtos/`：`Queue<T,N>`、`Semaphore`（FreeRTOS 的类型安全 inline 封装）
- `algo/`：`Pid<T>`、`LowPassFilter<T>`
- `proto/`：COBS 帧界定、CRC16/CRC32

**留在 `src/`**（与本项目强绑定）：

- 所有驱动（含具体 CAN ID、SPI 时序等）
- 协议消息定义
- 所有任务
- `entry.cpp`
