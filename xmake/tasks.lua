-- ─── fmt ─────────────────────────────────────────────────────────────────────
-- 用 clang-format 格式化 src/ 和 lib/ecx/ 下的所有 C/C++ 源文件。
task("fmt")
    set_menu {
        usage       = "xmake fmt",
        description = "用 clang-format 格式化 src/ 和 lib/ecx/ 下的源文件",
    }
    on_run(function()
        local files = {}
        local patterns = {
            "src/**.cpp", "src/**.hpp", "src/**.h",
            "lib/ecx/**.cpp", "lib/ecx/**.hpp", "lib/ecx/**.h",
        }
        for _, pat in ipairs(patterns) do
            for _, f in ipairs(os.files(pat)) do
                table.insert(files, f)
            end
        end
        if #files == 0 then
            print("没有找到需要格式化的文件")
            return
        end
        os.execv("clang-format", table.join({"-i", "--style=file"}, files))
        print(string.format("已格式化 %d 个文件", #files))
    end)
task_end()

-- ─── lint ─────────────────────────────────────────────────────────────────────
-- 用 clang-tidy 静态检查 src/ 下的源文件。
-- 前置条件：需先运行 `xmake project -k compile_commands` 生成编译数据库。
task("lint")
    set_menu {
        usage       = "xmake lint",
        description = "用 clang-tidy 静态检查 src/ 下的源文件（需先 xmake project -k compile_commands）",
    }
    on_run(function()
        local files = {}
        for _, f in ipairs(os.files("src/**.cpp")) do
            table.insert(files, f)
        end
        if #files == 0 then
            print("没有找到需要检查的文件")
            return
        end
        local dbpath = path.join(os.projectdir(), "build")
        os.execv("clang-tidy", table.join({"-p", dbpath}, files))
    end)
task_end()

-- ─── flash ────────────────────────────────────────────────────────────────────
-- 通过 OpenOCD + ST-Link 烧录固件。使用当前已配置的构建模式下的 .hex 产物。
-- 前置条件：需先运行 xmake 完成构建；目标机需通过 ST-Link 连接。
task("flash")
    set_menu {
        usage       = "xmake flash",
        description = "通过 OpenOCD + ST-Link 烧录固件（需先 xmake 构建）",
    }
    on_run(function()
        import("core.project.config")
        local buildir = config.buildir() or "build"
        local plat    = config.plat()    or "cross"
        local arch    = config.arch()    or "arm"
        local mode    = config.mode()    or "release"

        local hexfile = path.join(os.projectdir(), buildir, plat, arch, mode, "ec_demo.hex")
        if not os.isfile(hexfile) then
            raise("固件未找到：%s\n请先运行 xmake 构建项目", hexfile)
        end

        -- OpenOCD 在 Windows 下需要正斜杠路径
        local hexpath = hexfile:gsub("\\", "/")
        os.execv("openocd", {
            "-f", "interface/stlink.cfg",
            "-f", "target/stm32f4x.cfg",
            "-c", "program " .. hexpath .. " verify reset exit",
        })
    end)
task_end()
