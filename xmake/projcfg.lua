-- 项目级共享配置，供 xmake/ 下各模块的 on_run / on_build 等闭包通过
-- import("projcfg").get() 加载。
-- 注意：
-- 1) 模块名不能用 "config" 或 "project"——会与 xmake 内置的
--    core.project.config / core.project.project 冲突，import 会解析到内置模块。
-- 2) xmake 的 import() 沙盒会丢弃模块的 return 值，只暴露文件作用域里声明的
--    函数。因此本文件用 function get() 返回配置，而不是直接 return 一个 table。
-- project 名称和 target 名称由 xmake.lua 的 set_project() / target() 定义，
-- 调用方通过 project.targets() API 动态读取，不在此重复。

function get()
    return {
        -- ── 用户代码 glob（fmt / lint 共用，与 .clang-format/.clang-tidy 作用范围一致）
        user_globs = {
            "src/**.cpp", "src/**.hpp", "src/**.c", "src/**.h",
            "lib/**.cpp", "lib/**.hpp", "lib/**.c", "lib/**.h",
        },

        -- ── 烧录 ────────────────────────────────────────────────────────────────
        openocd_cfg_dir = "tools/openocd",  -- 相对项目根目录
    }
end
