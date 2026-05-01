-- ARM Cortex-M4 cross-compiler toolchain for xmake.
--
-- 探测顺序（由 find_program 统一处理）：
--   1. --sdk=<dir>  (xmake f --sdk=<dir>)
--   2. arm-none-eabi-gcc 已在 PATH 上
--   3. STM32CubeCLT / Arm GNU Toolchain 默认安装目录（Windows / Linux）
--
-- 在新机器上一次性配置：
--   xmake f -p cross -a arm -m release [--sdk=<path-to-GNU-tools-for-STM32>]
--
-- on_check / on_load 协议（参考 xmake 内置 toolchains/cross/{check,load}.lua）：
--   * on_check：在 `xmake f` 阶段被 platform:check() 调用一次。负责探测 SDK，
--     用 toolchain:config_set() 写入结果，并必须调用 toolchain:configs_save()
--     把 _CONFIGS 持久化到 .xmake/<host>/<arch>/cache/toolchain。漏掉
--     configs_save() 会让结果只活在当前进程内存里，下次 build 读到空 cache。
--   * on_load：每个 target 解析时调用，可能并发。只读 toolchain:config()
--     的值并配置 toolset；不应做发现/持久化逻辑。

toolchain("arm-none-eabi")
    set_kind("cross")

    on_check(function(toolchain)
        import("lib.detect.find_program")

        local sdkdir = toolchain:sdkdir()
        if not sdkdir or sdkdir == "" then
            local gcc = find_program("arm-none-eabi-gcc", {paths = {
                "C:/ST/STM32CubeCLT*/GNU-tools-for-STM32/bin",
                "D:/ST/STM32CubeCLT*/GNU-tools-for-STM32/bin",
                "C:/Program Files/STMicroelectronics/STM32CubeCLT*/GNU-tools-for-STM32/bin",
                "/usr/lib/gcc-arm-none-eabi*/bin",
                "/opt/gcc-arm-none-eabi*/bin",
                "/opt/arm-gnu-toolchain*/bin",
                "/opt/toolchains/arm-gnu-toolchain/arm-none-eabi*/bin",
            }})
            if gcc then
                -- gcc = <sdk>/bin/arm-none-eabi-gcc(.exe) → sdkdir = <sdk>
                sdkdir = path.directory(path.directory(gcc))
            end
        end

        if not sdkdir or sdkdir == "" then
            cprint("${red}error:${clear} 未找到 arm-none-eabi 工具链。\n" ..
                   "请把 arm-none-eabi-gcc 加入 PATH，或运行：\n" ..
                   "  xmake f --sdk=<path-to-GNU-tools-for-STM32>")
            return false
        end

        toolchain:config_set("sdkdir", sdkdir)
        toolchain:configs_save()
        return true
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
