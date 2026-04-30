toolchain("arm-none-eabi")
    set_kind("cross")

    on_load(function(toolchain)
        local prefix = "arm-none-eabi-"
        toolchain:set("toolset", "cc",      prefix .. "gcc")
        toolchain:set("toolset", "cxx",     prefix .. "g++")
        toolchain:set("toolset", "ld",      prefix .. "g++")
        toolchain:set("toolset", "ar",      prefix .. "ar")
        toolchain:set("toolset", "as",      prefix .. "gcc")
        toolchain:set("toolset", "objcopy", prefix .. "objcopy")
        toolchain:set("toolset", "size",    prefix .. "size")
        toolchain:set("toolset", "strip",   prefix .. "strip")

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
