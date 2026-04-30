#include "bsp/interface.h"

#include "FreeRTOS.h"
#include "task.h"

// Forward declarations — defined in tasks/*.cpp
void comm_task(void*);
void control_task(void*);
void monitor_task(void*);

namespace {

StaticTask_t s_comm_tcb;
StaticTask_t s_control_tcb;
StaticTask_t s_monitor_tcb;

StackType_t s_comm_stack[512];
StackType_t s_control_stack[256];
StackType_t s_monitor_stack[256];

}  // namespace

extern "C" void user_init() {
    xTaskCreateStatic(comm_task,    "comm",  512, nullptr, 3, s_comm_stack,    &s_comm_tcb);
    xTaskCreateStatic(control_task, "ctrl",  256, nullptr, 4, s_control_stack, &s_control_tcb);
    xTaskCreateStatic(monitor_task, "mon",   256, nullptr, 2, s_monitor_stack, &s_monitor_tcb);
}

extern "C" void user_error_handler() {
    __disable_irq();
    // Trap here — attach a debugger or observe the stuck state.
    for (;;) {}
}

extern "C" void user_assert_failed(uint8_t* file, uint32_t line) {
    (void)file;
    (void)line;
    user_error_handler();
}
