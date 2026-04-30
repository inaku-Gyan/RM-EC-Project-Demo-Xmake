# EC-Project-Demo

STM32F407 嵌入式机器人下位机。通过 USB CDC 与 Linux 上位机通信，控制电机等执行器。

**工具链**：arm-none-eabi-gcc · **构建**：Xmake · **语言**：C++20 / C11 · **RTOS**：FreeRTOS (CMSIS-RTOS v2) · **HAL**：STM32 HAL

---

## 目录结构

```
EC-Project-Demo/
├── xmake.lua / xmake/          # 构建系统
├── .clang-format / .clang-tidy # 代码风格与静态检查
├── .clangd                     # LSP 配置（clangd）
├── bsp/
│   ├── interface.h             # CubeMX → C++ 的唯一接口契约（C 兼容）
│   └── CubeMX/                 # CubeMX 生成，视为只读
├── src/                        # 本项目应用代码
│   ├── entry.cpp               # user_init()：创建所有任务
│   ├── driver/                 # 板载设备驱动（与本项目硬件强绑定）
│   ├── comm/                   # USB CDC 协议层
│   └── tasks/                  # FreeRTOS 任务入口（自由函数）
└── lib/
    └── ecx/                    # 跨项目共享中间件
        ├── rtos/               # FreeRTOS 类型安全薄封装
        ├── algo/               # PID、滤波器模板
        └── proto/              # COBS、CRC
```

---

## 代码来源与管理

| 目录              | 来源       | 修改策略                                         |
| ----------------- | ---------- | ------------------------------------------------ |
| `bsp/CubeMX/`     | CubeMX 生成 | 只改 USER CODE 段；重新配置外设用 CubeMX 重新生成 |
| `bsp/interface.h` | 手写       | 声明所有 CubeMX 可调用的 C++ 函数               |
| `src/`            | 手写       | 自由修改                                         |
| `lib/ecx/`        | 自研共享库 | 在独立 repo 里修改，本项目只消费                |

---

## CubeMX 集成策略

**原则：USER CODE 段只写一行调用，实现全部在 C++ 侧。**

`bsp/interface.h` 是 CubeMX 与 C++ 层之间的**唯一耦合点**。CubeMX 的每个回调只调用该头文件中声明的对应函数，具体逻辑全部在 `src/` 实现。

HAL RegisterCallback 统一在 `user_init()` 中注册，不动 `stm32f4xx_hal_msp.c`。

---

## 架构分层

```
src/tasks/    应用层：任务逻辑、状态机（与本机器人强绑定）
src/comm/     通信层：USB CDC 双缓冲、协议编解码
src/driver/   驱动层：具体设备驱动（DJI 电机、IMU 等）
lib/ecx/      共享层：RTOS 封装、算法模板、协议工具
bsp/CubeMX/   BSP 层：外设初始化、HAL、FreeRTOS、USB 栈（只读）
```

驱动层和共享层可直接调用 HAL 函数。零成本的 C++ 封装（模板、inline）值得做；引入间接跳转的封装（虚函数、`std::function`）不做。

---

## FreeRTOS 任务模式

**任务 = 自由函数 + 文件作用域匿名命名空间静态状态**，不用 class 包装。

所有任务在 `entry.cpp` 的 `user_init()` 里用 `xTaskCreateStatic` 创建，全部静态分配（`StaticTask_t` + 静态栈数组），禁止堆分配。

---

## USB CDC 双缓冲

RX 使用 ping-pong 双缓冲：`usb_cdc_rx_handler`（中断上下文）收到数据后立即切换端点缓冲区并重新 arm，数据通过 `xQueueSendFromISR` 入队，消除单缓冲的 NAK 窗口。

TX 使用二值信号量：`usb::send()` 获取信号量后发送，`usb_cdc_tx_cplt` 中断里归还，保证对上层同步。

---

## 构建系统

首次配置（一次性）：
```
xmake f -p cross -a arm -m release --sdk=<GNU-tools-for-STM32 路径>
xmake
```

工具链会尝试自动搜索 STM32CubeCLT 的常见安装路径；搜索不到时才需要手动指定 `--sdk`。

LSP（clangd）索引数据库：
```
xmake project -k compile_commands
```

---

## 代码规范

- **格式化**：`.clang-format`（Google style 变体），作用范围：`src/`、`lib/ecx/`
- **静态检查**：`.clang-tidy`，作用范围同上，`bsp/` 完全排除
- **注释语言**：中文

---

## 禁用的 C++ 特性

编译器 flag 强制禁用：

| 特性                      | Flag                      |
| ------------------------- | ------------------------- |
| 异常（`try/catch/throw`） | `-fno-exceptions`         |
| RTTI（`dynamic_cast`）    | `-fno-rtti`               |
| 线程安全静态初始化        | `-fno-threadsafe-statics` |

设计约束禁用（code review 把关）：虚函数、`std::function`、`std::vector/string`、`new/delete`、全局硬件对象。

推荐使用：`std::array`、`std::span`、`std::optional`、`std::atomic`、`constexpr/consteval`、Concepts、模板。

---

## ecx 边界

**放入 ecx**（与具体机器人无关，可跨项目复用）：RTOS 封装、算法模板（PID、滤波器）、协议工具（COBS、CRC）。

**留在 `src/`**（与本项目强绑定）：所有驱动、协议消息定义、所有任务、`entry.cpp`。
