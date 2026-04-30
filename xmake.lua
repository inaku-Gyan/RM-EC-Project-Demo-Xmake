includes("xmake/toolchain.lua")
includes("xmake/cubemx.lua")
includes("xmake/tasks.lua")

add_moduledirs("xmake")

-- target 名称在本文件内的唯一定义；tasks.lua 通过 project.targets() 动态读取，无需重复
local TARGET = "ec_demo"

set_project("ec-demo")
set_version("0.1.0")

-- 项目默认平台/架构/模式：跨平台编译到 ARM Cortex-M4，发布构建。
-- 设置后无需手动 `xmake f -p cross -a arm`，xmake 不会再自动检测 host 平台
-- （否则会回落到 mingw/msvc，导致工具链解析失败）。
set_defaultplat("cross")
set_defaultarchs("arm")
set_defaultmode("release")

set_toolchains("arm-none-eabi")

-- Global preprocessor defines (shared by both targets)
add_defines("STM32F407xx", "USE_HAL_DRIVER")

-- ─── CubeMX BSP static library ───────────────────────────────────────────────
-- Compiled as C11 with all warnings suppressed (third-party generated code).
-- Include paths are marked public so ec_demo inherits them automatically.
target("cubemx")
    set_kind("static")
    set_languages("c11")
    add_cflags("-w", {force = true})

    cubemx_add_files()
    cubemx_add_includes(true)
    -- Project root needed so CubeMX USER CODE can include "bsp/interface.h"
    add_includedirs(".", {public = false})
target_end()

-- ─── Main application ─────────────────────────────────────────────────────────
target(TARGET)
    set_kind("binary")
    set_languages("cxx20", "c11")

    add_files("src/**.cpp")

    -- Project root for "bsp/interface.h", lib/ecx headers, and src-relative includes
    add_includedirs(".", "lib/ecx", "src")

    add_deps("cubemx")

    -- C++ embedded constraints
    add_cxxflags("-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", {force = true})

    -- Strict warnings on application code
    add_cxxflags("-Wall", "-Wextra", "-Werror", {force = true})

    -- Linker script
    add_ldflags("-T" .. path.join(os.projectdir(), "bsp/CubeMX/STM32F407XX_FLASH.ld"), {force = true})

    -- Map file for size analysis
    add_ldflags("-Wl,-Map=$(builddir)/" .. TARGET .. ".map,--cref", {force = true})

    -- LTO in release mode for smaller/faster binary
    if is_mode("release") then
        add_cflags("-flto")
        add_cxxflags("-flto")
        add_ldflags("-flto")
    end

    -- Debug 模式：-Og 比 -O0 更适合嵌入式（节省 Flash），-g 保留调试符号
    if is_mode("debug") then
        add_defines("DEBUG")
        add_cflags("-Og", "-g", {force = true})
        add_cxxflags("-Og", "-g", {force = true})
    end

    -- Post-build: generate .hex/.bin and print section sizes
    after_build(function(target)
        local elf = target:targetfile()
        local dir = path.directory(elf)
        local stem = path.basename(elf)
        os.execv("arm-none-eabi-objcopy", {"-O", "ihex",   elf, path.join(dir, stem .. ".hex")})
        os.execv("arm-none-eabi-objcopy", {"-O", "binary", elf, path.join(dir, stem .. ".bin")})
        os.execv("arm-none-eabi-size", {"--format=berkeley", elf})
    end)
target_end()
