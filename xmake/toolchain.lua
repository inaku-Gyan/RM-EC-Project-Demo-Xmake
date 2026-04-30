-- ARM Cortex-M4 cross-compiler toolchain for xmake.
--
-- Auto-discovery order（由 find_program 统一处理）：
--   1. --sdk=<dir>  (或 xmake f --sdk=<dir>，保存在 .xmake/)
--   2. arm-none-eabi-gcc 已在 PATH 上
--   3. STM32CubeCLT / Arm GNU Toolchain 默认安装目录（Windows / Linux）
--
-- 在新机器上一次性配置：
--   xmake f --sdk=<path-to-GNU-tools-for-STM32>

toolchain("arm-none-eabi")
    set_kind("cross")

    -- on_check：主线程一次性探测 SDK 并把 sdkdir 持久化到 toolchain 配置。
    -- on_load：每个 target 解析时（可能并发）只读取已保存的 sdkdir，避免竞态。
    on_check(function(toolchain)
        import("lib.detect.find_program")

        local prefix = "arm-none-eabi-"

        -- 1) 显式 --sdk：xmake cross 平台内置 check 已经验证过 sdk 是否包含
        --    交叉编译器；走到这里说明 sdkdir 有效，直接采纳即可。
        local sdkdir = toolchain:sdkdir()
        if sdkdir and sdkdir ~= "" then
            toolchain:config_set("sdkdir", sdkdir)
            return true
        end

        -- 2/3) find_program 同时搜 PATH 与候选安装目录（支持 glob）
        local gcc = find_program(prefix .. "gcc", {paths = {
            -- STM32CubeCLT —— Windows 常见安装位置
            "C:/ST/STM32CubeCLT*/GNU-tools-for-STM32/bin",
            "D:/ST/STM32CubeCLT*/GNU-tools-for-STM32/bin",
            "C:/Program Files/STMicroelectronics/STM32CubeCLT*/GNU-tools-for-STM32/bin",
            -- Arm GNU Toolchain —— Linux 常见路径
            "/usr/lib/gcc-arm-none-eabi*/bin",
            "/opt/gcc-arm-none-eabi*/bin",
            "/opt/arm-gnu-toolchain*/bin",
        }})

        if gcc then
            -- gcc = <sdk>/bin/arm-none-eabi-gcc(.exe) → sdkdir = <sdk>
            sdkdir = path.directory(path.directory(gcc))
            toolchain:config_set("sdkdir", sdkdir)
            return true
        end

        cprint("${red}error:${clear} 未找到 arm-none-eabi 工具链。\n" ..
               "请把 arm-none-eabi-gcc 加入 PATH，或运行：\n" ..
               "  xmake f --sdk=<path-to-GNU-tools-for-STM32>")
        return false
    end)

    on_load(function(toolchain)
        local prefix = "arm-none-eabi-"
        local sdkdir = toolchain:config("sdkdir") or toolchain:sdkdir()
        if not sdkdir or sdkdir == "" then
            raise("arm-none-eabi 工具链 sdkdir 未配置；请重新运行 xmake f")
        end
        toolchain:set("sdkdir", sdkdir)

        -- 始终用绝对路径设置 toolset。
        -- 注意：不能用 path.join(sdkdir, "bin", prefix)——尾部带 "-" 不是有效目录段，
        -- path.join 会把它丢掉。先 join 出 bindir，再字符串拼接 prefix+name。
        local bindir = path.join(sdkdir, "bin")
        local function tool(name) return path.join(bindir, prefix .. name) end
        toolchain:set("toolset", "cc",      tool("gcc"))
        toolchain:set("toolset", "cxx",     tool("g++"))
        toolchain:set("toolset", "ld",      tool("g++"))
        toolchain:set("toolset", "ar",      tool("ar"))
        toolchain:set("toolset", "as",      tool("gcc"))
        toolchain:set("toolset", "objcopy", tool("objcopy"))
        toolchain:set("toolset", "size",    tool("size"))
        toolchain:set("toolset", "strip",   tool("strip"))

        local cpu_flags = {
            "-mcpu=cortex-m4",
            "-mthumb",
            "-mfpu=fpv4-sp-d16",
            "-mfloat-abi=hard",
        }
        for _, flag in ipairs(cpu_flags) do
            toolchain:add("cflags",   flag)
            toolchain:add("cxxflags", flag)
            toolchain:add("asflags",  flag)
            toolchain:add("ldflags",  flag)
        end

        toolchain:add("cflags",   "-fdata-sections", "-ffunction-sections")
        toolchain:add("cxxflags", "-fdata-sections", "-ffunction-sections")
        toolchain:add("ldflags",  "-Wl,--gc-sections")
        toolchain:add("ldflags",  "-specs=nano.specs", "-specs=nosys.specs")
        toolchain:add("ldflags",  "-Wl,--start-group", "-lc", "-lm", "-lstdc++", "-lsupc++", "-Wl,--end-group")
    end)
toolchain_end()
