-- ARM Cortex-M4 cross-compiler toolchain for xmake.
--
-- Auto-discovery order:
--   1. arm-none-eabi-gcc already on PATH
--   2. --sdk=<dir>  (or xmake f --sdk=<dir>, saved in .xmake/)
--   3. STM32CubeCLT at its default install locations (Windows / Linux)
--
-- To configure permanently on a new machine:
--   xmake f -p cross -a arm --sdk=<path-to-GNU-tools-for-STM32>

toolchain("arm-none-eabi")
    set_kind("cross")

    -- xmake 在某些命令路径（如 xmake project）下要求 toolchain 显式 check
    -- 通过后才会被 load。返回 true 表示我们自己负责在 on_load 里定位工具链，
    -- 不依赖 xmake 的标准探测流程。
    on_check(function() return true end)

    on_load(function(toolchain)
        local prefix = "arm-none-eabi-"

        -- Try auto-detecting the SDK if not already set and not on PATH.
        local sdkdir = toolchain:sdkdir()
        if (not sdkdir or sdkdir == "") and not os.iorun("where " .. prefix .. "gcc") then
            local candidates = {
                -- STM32CubeCLT — Windows default and common custom locations
                "C:/ST/STM32CubeCLT*/GNU-tools-for-STM32",
                "D:/ST/STM32CubeCLT*/GNU-tools-for-STM32",
                "C:/Program Files/STMicroelectronics/STM32CubeCLT*/GNU-tools-for-STM32",
                "D:/InstalledSoftwares/DevTools/STM32CubeCLT*/GNU-tools-for-STM32",
                -- Arm GNU Toolchain — Linux
                "/usr/lib/gcc-arm-none-eabi*",
                "/opt/gcc-arm-none-eabi*",
                "/opt/arm-gnu-toolchain*",
            }
            for _, pattern in ipairs(candidates) do
                local dirs = os.filedirs(pattern)
                if dirs and #dirs > 0 then
                    sdkdir = dirs[#dirs]  -- pick the newest (last sorted entry)
                    break
                end
            end
            if sdkdir and os.isdir(sdkdir) then
                toolchain:set("sdkdir", sdkdir)
            end
        end

        local binpfx = sdkdir and path.join(sdkdir, "bin", prefix) or prefix
        toolchain:set("toolset", "cc",      binpfx .. "gcc")
        toolchain:set("toolset", "cxx",     binpfx .. "g++")
        toolchain:set("toolset", "ld",      binpfx .. "g++")
        toolchain:set("toolset", "ar",      binpfx .. "ar")
        toolchain:set("toolset", "as",      binpfx .. "gcc")
        toolchain:set("toolset", "objcopy", binpfx .. "objcopy")
        toolchain:set("toolset", "size",    binpfx .. "size")
        toolchain:set("toolset", "strip",   binpfx .. "strip")

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
