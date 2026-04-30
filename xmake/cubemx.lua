-- Helper functions for the cubemx static library target.
-- Call cubemx_add_files() and cubemx_add_includes() from inside a target() block.

local BSP = "bsp/CubeMX"

function cubemx_add_files()
    -- CubeMX application sources
    add_files(BSP .. "/Src/*.c")

    -- STM32 HAL driver sources
    add_files(BSP .. "/Drivers/STM32F4xx_HAL_Driver/Src/*.c")

    -- USB Device Library
    add_files(BSP .. "/Middlewares/ST/STM32_USB_Device_Library/Class/CDC/Src/*.c")
    add_files(BSP .. "/Middlewares/ST/STM32_USB_Device_Library/Core/Src/*.c")

    -- FreeRTOS kernel
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/croutine.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/event_groups.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/list.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/queue.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/stream_buffer.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/tasks.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/timers.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2/cmsis_os2.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F/port.c")
    add_files(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/portable/MemMang/heap_4.c")

    -- Startup assembly (assembled as C with preprocessor)
    add_files(BSP .. "/startup_stm32f407xx.s")
end

function cubemx_add_includes(pub)
    local opt = {public = pub}
    add_includedirs(BSP .. "/Inc",                                                                    opt)
    add_includedirs(BSP .. "/Drivers/CMSIS/Device/ST/STM32F4xx/Include",                             opt)
    add_includedirs(BSP .. "/Drivers/CMSIS/Include",                                                  opt)
    add_includedirs(BSP .. "/Drivers/STM32F4xx_HAL_Driver/Inc",                                      opt)
    add_includedirs(BSP .. "/Middlewares/ST/STM32_USB_Device_Library/Class/CDC/Inc",                  opt)
    add_includedirs(BSP .. "/Middlewares/ST/STM32_USB_Device_Library/Core/Inc",                       opt)
    add_includedirs(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/include",                        opt)
    add_includedirs(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2",                  opt)
    add_includedirs(BSP .. "/Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F",          opt)
end
