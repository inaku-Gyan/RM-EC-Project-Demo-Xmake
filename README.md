# EC-Project-Demo

STM32F407 嵌入式机器人下位机。通过 USB CDC 与 Linux 上位机通信，控制电机等执行器。

| 组件     | 选型                                |
| -------- | ----------------------------------- |
| MCU      | STM32F407 (Cortex-M4F, FPU)         |
| 工具链   | arm-none-eabi-gcc                   |
| 构建系统 | [Xmake](https://xmake.io) ≥ 2.8     |
| 语言     | C++20（应用层） / C11（CubeMX BSP） |
| RTOS     | FreeRTOS（CMSIS-RTOS v2 API）       |
| HAL      | STM32CubeMX + STM32 HAL             |

---

## 一、配置开发环境

### 1. 安装工具链

至少需要：**arm-none-eabi-gcc**（含 `g++`、`ld`、`objcopy`、`size`） 和 **Xmake**。

| 平台    | 推荐方式                                                                                                                               |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Windows | 安装 [STM32CubeCLT](https://www.st.com/en/development-tools/stm32cubeclt.html)（自带 GNU-tools-for-STM32 + OpenOCD）                   |
| Linux   | `apt install gcc-arm-none-eabi openocd`，或下载 [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads) |
| macOS   | `brew install --cask gcc-arm-embedded` + `brew install openocd`                                                                        |

Xmake 安装：参见 [xmake.io 安装文档](https://xmake.io/#/guide/installation)。

烧录所需的 **OpenOCD** 是可选项，仅当使用 `xmake flash` 才需要。探针配置文件位于 [tools/openocd/](tools/openocd/)，已提供 `cmsis-dap` / `stlink` / `jlink` 三种。

### 2. 首次配置 Xmake

在项目根目录下执行一次：

```bash
xmake f -p cross -a arm -m release
```

工具链会自动搜索：
1. `--sdk=<dir>` 显式指定的路径
2. `arm-none-eabi-gcc` 是否已在 `PATH`
3. STM32CubeCLT / Arm GNU Toolchain 的常见安装位置

只有当上述都搜不到时，才需要手动指定 SDK：

```bash
xmake f -p cross -a arm -m release --sdk=<path-to-GNU-tools-for-STM32>
```

配置结果会缓存在 `.xmake/`（已在 `.gitignore` 里），每台机器配置一次即可。

### 3. 构建

```bash
xmake              # 编译，产物在 build/cross/arm/release/
xmake -r           # 重新构建
xmake distclean    # 清理 build/ 与 .xmake/
xmake distclean -a # 连 compile_commands.json 与 .cache/ 一并清掉
```

构建产物：`ec_demo.elf` / `.hex` / `.bin` / `.map`。`after_build` 钩子会自动调用 `objcopy` 生成 hex/bin，并打印 `arm-none-eabi-size` 的段大小报告。

### 4. 烧录

```bash
xmake flash                       # 默认使用 cmsis-dap
xmake flash --probe=stlink        # 切换 ST-Link
xmake flash --probe=jlink         # 切换 J-Link
xmake flash --port=<serial>       # 多探针环境下指定适配器序列号
xmake flash --file=custom.hex     # 烧录任意 hex（默认是当前构建产物）
```

底层调用 OpenOCD 的 `program ... verify reset exit`。

### 5. IDE 配置（VSCode）

推荐扩展见 [.vscode/extensions.json](.vscode/extensions.json)：

- **clangd**（`llvm-vs-code-extensions.vscode-clangd`）—— LSP 与格式化
- **xmake**（`xmake-vscode.xmake`）—— 构建集成
- **Cortex-Debug**（`marus25.cortex-debug`）—— 在线调试

复制 `.vscode/settings.example.json` 为 `.vscode/settings.json`（后者已被 gitignore），即可获得 clangd + Xmake 的完整配置。clangd 使用 `--query-driver` 让 ARM 工具链头文件正确解析。

生成 / 更新 LSP 索引数据库（`compile_commands.json`，clangd 自动加载）：

```bash
xmake project -k compile_commands
```

新增 / 删除源文件后重新执行一次。

---

## 二、开发流程

### 1. 目录速览

```
src/                  本项目应用代码（自由修改）
├── entry.cpp         user_init()：入口，集中创建所有任务
├── driver/           板载设备驱动（与硬件强绑定）
├── comm/             USB CDC 协议层
└── tasks/            FreeRTOS 任务入口（自由函数）

lib/ecx/              跨项目共享中间件（与具体机器人无关）
├── rtos/             FreeRTOS 类型安全薄封装
├── algo/             PID、滤波器等算法模板
└── proto/            COBS、CRC 等协议工具

bsp/
├── interface.h       CubeMX → C++ 的唯一接口契约（C 兼容）
└── CubeMX/           CubeMX 生成（视为只读，仅在 USER CODE 段加调用）

xmake/                构建脚本（toolchain / cubemx / 自定义任务）
tools/openocd/        烧录探针配置
```

各目录的修改策略详见 [CLAUDE.md](CLAUDE.md)。

### 2. CubeMX 集成原则

> **USER CODE 段只写一行调用，实现全部在 C++ 侧。**

[bsp/interface.h](bsp/interface.h) 是 CubeMX 与 C++ 层之间的唯一耦合点：所有 CubeMX 回调只调用该头文件中声明的 C 函数，具体逻辑在 `src/` 用 C++ 实现。HAL `RegisterCallback` 统一在 `user_init()` 中注册，**不动 `stm32f4xx_hal_msp.c`**。

需要重新配置外设时：用 CubeMX 打开 [bsp/CubeMX/CubeMX.ioc](bsp/CubeMX/CubeMX.ioc) 重新生成；不要手改 `bsp/CubeMX/Src/`、`bsp/CubeMX/Inc/` 里的非 USER CODE 代码。

### 3. FreeRTOS 任务模式

- **任务 = 自由函数 + 文件作用域匿名命名空间静态状态**，不用 class 包装。
- 全部任务在 `entry.cpp` 的 `user_init()` 里用 `xTaskCreateStatic` 创建，**全静态分配**（`StaticTask_t` + 静态栈数组）。
- **禁止 RTOS 对象的堆分配**。

### 4. C++ 限制（嵌入式约束）

编译器 flag 强制禁用：

| 特性                     | Flag                      |
| ------------------------ | ------------------------- |
| 异常 (`try/catch/throw`) | `-fno-exceptions`         |
| RTTI (`dynamic_cast`)    | `-fno-rtti`               |
| 线程安全静态初始化       | `-fno-threadsafe-statics` |

应用代码同时启用 `-Wall -Wextra -Werror`：**任何警告都是错误**。

设计约束禁用（code review 把关）：虚函数、`std::function`、`std::vector / std::string`、`new / delete`、全局硬件对象。

推荐使用：`std::array`、`std::span`、`std::optional`、`std::atomic`、`constexpr / consteval`、Concepts、模板。

### 5. 代码风格

- **格式化**：[.clang-format](.clang-format)（Google 变体，4 空格缩进，列宽 100，指针左对齐）
- **静态检查**：[.clang-tidy](.clang-tidy)（`modernize-* / bugprone-* / readability-* / performance-*`，`WarningsAsErrors: "*"`）
- **作用范围**：仅 `src/` 与 `lib/ecx/`；`bsp/` 完全排除
- **命名规则**（来自 clang-tidy）：
  - 类型 `CamelCase`，函数 `lower_case`，变量 `lower_case`
  - 私有成员后缀 `_`
  - `constexpr` 常量 `UPPER_CASE`，枚举值 `CamelCase`
- **注释语言**：中文

提交前务必本地跑一遍：

```bash
xmake fmt              # clang-format 自动修复
xmake fmt --check      # 仅检查（CI / 提前发现差异）

xmake lint             # clang-tidy 自动修复
xmake lint --check     # 仅报告（不改代码）
```

`xmake lint` 依赖 `compile_commands.json`，先跑一次 `xmake project -k compile_commands`。

### 6. ecx 边界

- **放进 `lib/ecx/`**：与具体机器人无关、可跨项目复用的代码（RTOS 封装、算法模板、协议工具）。
- **留在 `src/`**：所有驱动、协议消息定义、所有任务、`entry.cpp`。

ecx 在独立 repo 中开发与维护；本项目只消费、不直接修改 `lib/ecx/`。

---

## 三、常用命令速查

```bash
# 配置
xmake f -p cross -a arm -m release         # 一次性配置（自动找工具链）
xmake f --sdk=<path>                       # 工具链找不到时手动指定

# 构建
xmake                                      # 编译
xmake -r                                   # 重建
xmake distclean [-a]                       # 清理（-a 连同索引一并清）

# 烧录
xmake flash [--probe=cmsis-dap|stlink|jlink] [--port=<serial>] [--file=<hex>]

# 代码规范
xmake fmt  [--check]                       # clang-format
xmake lint [--check]                       # clang-tidy（需先生成 compile_commands.json）

# IDE
xmake project -k compile_commands          # 生成 / 更新 clangd 索引数据库
```
