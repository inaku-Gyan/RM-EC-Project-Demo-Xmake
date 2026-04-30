-- ─── fmt ─────────────────────────────────────────────────────────────────────
-- 默认自动修复；--check 只报告差异，非零退出码表示未通过。
task("fmt")
    set_menu {
        usage       = "xmake fmt [--check]",
        description = "用 clang-format 格式化用户代码",
        options = {
            {nil, "check", "k", nil, "仅检查格式是否合规，不修改文件"},
        },
    }
    on_run(function()
        import("core.base.option")

        local files = {}
        for _, pat in ipairs({
            "src/**.cpp", "src/**.hpp", "src/**.h",
            "lib/ecx/**.cpp", "lib/ecx/**.hpp", "lib/ecx/**.h",
        }) do
            for _, f in ipairs(os.files(pat)) do
                table.insert(files, f)
            end
        end
        if #files == 0 then
            print("没有找到需要处理的文件")
            return
        end

        if option.get("check") then
            -- --dry-run --Werror: 有差异时输出 diff 并以非零退出码退出
            os.execv("clang-format", table.join({"--dry-run", "--Werror", "--style=file"}, files))
            cprint("${green}格式检查通过（%d 个文件）${clear}", #files)
        else
            os.execv("clang-format", table.join({"-i", "--style=file"}, files))
            cprint("${green}已格式化 %d 个文件${clear}", #files)
        end
    end)
task_end()

-- ─── lint ─────────────────────────────────────────────────────────────────────
-- 默认自动修复（--fix --fix-errors）；--check 只报告，不改动文件。
-- 前置条件：需先运行 `xmake project -k compile_commands` 生成编译数据库。
task("lint")
    set_menu {
        usage       = "xmake lint [--check]",
        description = "用 clang-tidy 静态检查并自动修复用户代码",
        options = {
            {nil, "check", "k", nil, "仅报告问题，不自动修复代码"},
        },
    }
    on_run(function()
        import("core.base.option")

        local files = {}
        for _, f in ipairs(os.files("src/**.cpp")) do
            table.insert(files, f)
        end
        if #files == 0 then
            print("没有找到需要检查的文件")
            return
        end

        local dbpath = path.join(os.projectdir(), "build")
        if not os.isdir(dbpath) or not os.isfile(path.join(dbpath, "compile_commands.json")) then
            raise("编译数据库不存在，请先运行：xmake project -k compile_commands")
        end

        local args = {"-p", dbpath}
        if not option.get("check") then
            -- --fix-errors 同时处理含错误级别诊断的修复
            table.insert(args, "--fix")
            table.insert(args, "--fix-errors")
        end
        os.execv("clang-tidy", table.join(args, files))
    end)
task_end()

-- ─── flash ────────────────────────────────────────────────────────────────────
-- 通过 OpenOCD 烧录固件。探针配置来自 tools/openocd/<probe>.cfg。
-- 示例：
--   xmake flash
--   xmake flash --probe=cmsis-dap
--   xmake flash --probe=stlink --port=<serial> --file=custom.hex
task("flash")
    set_menu {
        usage       = "xmake flash [--probe=cmsis-dap] [--file=<path>] [--port=<serial>]",
        description = "通过 OpenOCD 烧录固件到目标板",
        options = {
            {'p', "probe", "kv", "cmsis-dap",
             "调试探针类型（默认：cmsis-dap）\n"
          .. "                               可选：stlink | cmsis-dap | jlink"},
            {'f', "file",  "kv", nil,
             "固件 .hex 路径（可选，默认使用当前构建模式的产物）"},
            {nil, "port",  "kv", nil,
             "适配器序列号（可选，多探针环境下用于选择特定设备）"},
        },
    }
    on_run(function()
        import("core.base.option")
        import("core.project.config")

        local probe = option.get("probe")
        local port  = option.get("port")

        -- ── 确定固件路径 ────────────────────────────────────────────────────
        local hexfile = option.get("file")
        if not hexfile then
            local buildir = config.buildir() or "build"
            local plat    = config.plat()    or "cross"
            local arch    = config.arch()    or "arm"
            local mode    = config.mode()    or "release"
            hexfile = path.join(os.projectdir(), buildir, plat, arch, mode, "ec_demo.hex")
        end
        if not os.isfile(hexfile) then
            raise("固件未找到：%s\n请先运行 xmake 构建项目", hexfile)
        end

        -- ── 确定探针配置文件 ─────────────────────────────────────────────────
        local cfgfile = path.join(os.projectdir(), "tools", "openocd", probe .. ".cfg")
        if not os.isfile(cfgfile) then
            raise("探针配置不存在：%s\n支持的探针：stlink | cmsis-dap | jlink", cfgfile)
        end

        -- OpenOCD 在 Windows 下需要正斜杠；Tcl {} 引用处理路径中的空格
        local hexpath = hexfile:gsub("\\", "/")
        local cfgpath = cfgfile:gsub("\\", "/")

        -- ── 组装 OpenOCD 参数 ────────────────────────────────────────────────
        local args = {}
        -- adapter serial 必须在 -f 加载接口之前指定
        if port then
            table.insert(args, "-c")
            table.insert(args, string.format("adapter serial %s", port))
        end
        table.insert(args, "-f")
        table.insert(args, cfgpath)
        table.insert(args, "-c")
        table.insert(args, string.format("program {%s} verify reset exit", hexpath))

        os.execv("openocd", args)
    end)
task_end()
