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
        local C = import("projcfg", {anonymous = true}).get()

        local files = {}
        for _, pat in ipairs(C.user_globs) do
            for _, f in ipairs(os.files(path.join(os.projectdir(), pat))) do
                table.insert(files, f)
            end
        end
        if #files == 0 then
            print("没有找到需要处理的文件")
            return
        end

        if option.get("check") then
            -- --dry-run --Werror: 有差异时输出 diff 并以非零退出码退出
            local code = os.execv("clang-format",
                table.join({"--dry-run", "--Werror", "--style=file"}, files),
                {try = true})
            if code ~= 0 then
                raise("格式检查未通过，请运行 `xmake fmt` 自动修复")
            end
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
        local C = import("projcfg", {anonymous = true}).get()

        local files = {}
        for _, pat in ipairs(C.user_globs) do
            for _, f in ipairs(os.files(path.join(os.projectdir(), pat))) do
                table.insert(files, f)
            end
        end
        if #files == 0 then
            print("没有找到需要检查的文件")
            return
        end

        -- xmake project -k compile_commands 默认输出到项目根（与 .clangd 约定一致）
        local dbpath = os.projectdir()
        if not os.isfile(path.join(dbpath, "compile_commands.json")) then
            raise("编译数据库不存在，请先运行：xmake project -k compile_commands")
        end

        local args = {"-p", dbpath}
        if not option.get("check") then
            -- --fix-errors 同时处理含错误级别诊断的修复
            table.insert(args, "--fix")
            table.insert(args, "--fix-errors")
        end
        local code = os.execv("clang-tidy", table.join(args, files), {try = true})
        if code ~= 0 then
            if option.get("check") then
                raise("静态检查未通过，请运行 `xmake lint` 自动修复或人工处理")
            else
                raise("clang-tidy 退出码 %d", code)
            end
        end
    end)
task_end()

-- ─── flash ────────────────────────────────────────────────────────────────────
-- 通过 OpenOCD 烧录固件。探针配置来自 xmake/projcfg.lua 的 openocd_cfg_dir。
-- binary target 名称通过 project.targets() 动态获取，无需硬编码。
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
        import("core.project.project")
        local C = import("projcfg", {anonymous = true}).get()

        local probe = option.get("probe")
        local port  = option.get("port")

        -- ── 确定固件路径 ────────────────────────────────────────────────────
        local hexfile = option.get("file")
        if not hexfile then
            -- 从 project API 读取 binary target 名称，与 xmake.lua 保持同步
            local bin_target
            for _, t in pairs(project.targets()) do
                if t:kind() == "binary" then
                    bin_target = t
                    break
                end
            end
            assert(bin_target, "未找到 binary target，请确认项目已配置（xmake f ...）")

            local buildir = config.buildir() or "build"
            local plat    = config.plat()    or "cross"
            local arch    = config.arch()    or "arm"
            local mode    = config.mode()    or "release"
            hexfile = path.join(os.projectdir(), buildir, plat, arch, mode,
                                bin_target:name() .. ".hex")
        end
        if not os.isfile(hexfile) then
            raise("固件未找到：%s\n请先运行 xmake 构建项目", hexfile)
        end

        -- ── 确定探针配置文件 ─────────────────────────────────────────────────
        local cfgfile = path.join(os.projectdir(), C.openocd_cfg_dir, probe .. ".cfg")
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
