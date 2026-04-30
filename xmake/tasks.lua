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
        import("core.project.config")
        import("core.project.project")
        local C = import("projcfg", {anonymous = true}).get()

        -- 只把源文件（.cpp/.c）喂给 clang-tidy；头文件没有自己的 compile command，
        -- 单独传会用默认 -std= 解析（C++20 特性如 <concepts>/<span> 会失败）。
        -- 头文件通过 .clang-tidy 的 HeaderFilterRegex 在被 .cpp 包含时一并检查。
        local files = {}
        for _, pat in ipairs(C.user_globs) do
            local ext = pat:match("%.([^%.]+)$")
            if ext == "cpp" or ext == "c" then
                for _, f in ipairs(os.files(path.join(os.projectdir(), pat))) do
                    table.insert(files, f)
                end
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

        -- ── 注入交叉编译工具链的内置 include 路径 ─────────────────────────────
        -- clang-tidy 用 libclang 解析源文件，但不知道 arm-none-eabi-g++ 的内置
        -- 头文件目录（C/C++ stdlib）。不注入会得到一堆 "'cstdint' file not found"
        -- 之类的 clang-diagnostic-error，并连带触发 enum-size 等基于 AST 的
        -- 误报（因为 uint8_t 未声明，enum 退化成 int）。
        -- 做法：从 xmake 已配置的 binary target 拿到工具链路径，跑
        -- g++ -E -v 解析 "#include <...> search starts here:" 段。
        -- 等价于 clangd 的 --query-driver。
        config.load()
        local extra_args = {}
        local sdkdir
        for _, t in pairs(project.targets()) do
            if t:kind() == "binary" then
                for _, tc in ipairs(t:toolchains()) do
                    sdkdir = tc:config("sdkdir") or tc:sdkdir()
                    if sdkdir then break end
                end
                break
            end
        end
        if sdkdir then
            local cxx = path.join(sdkdir, "bin",
                "arm-none-eabi-g++" .. (is_host("windows") and ".exe" or ""))
            if os.isexec(cxx) then
                local null_dev = is_host("windows") and "NUL" or "/dev/null"
                local _, errdata = os.iorunv(cxx,
                    {"-E", "-x", "c++", "-v", null_dev}, {try = true})
                if errdata then
                    local in_section = false
                    for line in errdata:gmatch("[^\r\n]+") do
                        if line:find("End of search list", 1, true) then
                            in_section = false
                        elseif in_section then
                            local p = line:gsub("^%s+", ""):gsub("%s+$", "")
                            if p ~= "" then
                                table.insert(extra_args,
                                    "--extra-arg=-isystem" .. p)
                            end
                        elseif line:find("#include <...> search starts here",
                                         1, true) then
                            in_section = true
                        end
                    end
                end
            end
        end

        local args = {"-p", dbpath}
        for _, a in ipairs(extra_args) do
            table.insert(args, a)
        end
        if not option.get("check") then
            -- --fix-errors 同时处理含错误级别诊断的修复
            table.insert(args, "--fix")
            table.insert(args, "--fix-errors")
            table.insert(args, "--fix-notes")
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

-- ─── distclean ───────────────────────────────────────────────────────────────
-- 比 xmake 内置 clean 更彻底：清掉所有构建产物和构建状态。
-- 默认保留 compile_commands.json 和 .cache/（clangd 索引）—— 它们是 IDE
-- 开发体验数据，与磁盘上的 .o/.elf 没耦合，删了只是徒增"重建索引"成本。
-- 用 --all 可以连同它们一起清掉，恢复到接近首次 clone 的状态。
task("distclean")
    set_menu {
        usage       = "xmake distclean [-a|--all]",
        description = "清理构建产物：build/、.xmake/（--all 同时清 compile_commands.json 和 .cache/）",
        options = {
            {'a', "all", "k", nil, "更彻底：连 compile_commands.json 和 .cache/（clangd 索引）一起删"},
        },
    }
    on_run(function()
        import("core.base.option")
        local targets = {"build", ".xmake"}
        if option.get("all") then
            table.insert(targets, "compile_commands.json")
            table.insert(targets, ".cache")
        end
        local removed = {}
        for _, rel in ipairs(targets) do
            local abs = path.join(os.projectdir(), rel)
            if os.exists(abs) then
                os.tryrm(abs)
                table.insert(removed, rel)
            end
        end
        if #removed == 0 then
            print("已是干净状态")
        else
            cprint("${green}已清理：${clear}")
            for _, p in ipairs(removed) do
                cprint("  - %s", p)
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

        -- OpenOCD 在 Windows 下需要正斜杠（哪怕是 Windows 平台）；
        -- Tcl {} 引用处理路径中的空格。path.unix() 强制转成正斜杠。
        local hexpath = path.unix(hexfile)
        local cfgpath = path.unix(cfgfile)

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
