#include "usb_comm.hpp"

#include <cstring>

extern "C" {
#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "usb_device.h"
#include "usbd_cdc_if.h"
}

namespace usb {

namespace {

alignas(4) uint8_t rx_buf[2][64];
int rx_active = 0;

alignas(4) uint8_t tx_buf[512];
StaticSemaphore_t tx_sem_storage;
SemaphoreHandle_t tx_sem = nullptr;

constexpr size_t kRxQueueDepth = 4;
StaticQueue_t rx_q_storage;
uint8_t rx_q_buf[kRxQueueDepth * sizeof(RxPacket)];
QueueHandle_t rx_queue = nullptr;

}  // namespace

// ─── ISR-callable hooks (called from CubeMX CDC callbacks) ────────────────────

extern "C" void usb_cdc_init_rx() {
    // Create TX semaphore; start as "given" so the first send proceeds immediately.
    tx_sem = xSemaphoreCreateBinaryStatic(&tx_sem_storage);
    xSemaphoreGive(tx_sem);

    rx_queue = xQueueCreateStatic(kRxQueueDepth, sizeof(RxPacket), rx_q_buf, &rx_q_storage);

    // Point the USB endpoint at ping-pong buffer 0 and arm it.
    USBD_CDC_SetRxBuffer(&hUsbDeviceFS, rx_buf[rx_active]);
    USBD_CDC_ReceivePacket(&hUsbDeviceFS);
}

extern "C" void usb_cdc_rx_handler(uint8_t* buf, uint32_t len) {
    // Switch to the other buffer before re-arming so the USB core never writes
    // into the buffer we are about to enqueue.
    int prev = rx_active;
    rx_active ^= 1;
    USBD_CDC_SetRxBuffer(&hUsbDeviceFS, rx_buf[rx_active]);
    USBD_CDC_ReceivePacket(&hUsbDeviceFS);

    if (rx_queue == nullptr) return;

    RxPacket pkt;
    pkt.len = len < sizeof(pkt.data) ? len : sizeof(pkt.data);
    std::memcpy(pkt.data, buf, pkt.len);
    (void)prev;

    BaseType_t woken = pdFALSE;
    xQueueSendFromISR(rx_queue, &pkt, &woken);
    portYIELD_FROM_ISR(woken);
}

extern "C" void usb_cdc_tx_cplt() {
    if (tx_sem == nullptr) return;
    BaseType_t woken = pdFALSE;
    xSemaphoreGiveFromISR(tx_sem, &woken);
    portYIELD_FROM_ISR(woken);
}

// ─── Public API ───────────────────────────────────────────────────────────────

bool send(std::span<const uint8_t> data) {
    if (data.size() > sizeof(tx_buf)) return false;
    xSemaphoreTake(tx_sem, portMAX_DELAY);
    std::memcpy(tx_buf, data.data(), data.size());
    return CDC_Transmit_FS(tx_buf, static_cast<uint16_t>(data.size())) == USBD_OK;
}

bool rx_receive(RxPacket& pkt, TickType_t timeout) {
    return xQueueReceive(rx_queue, &pkt, timeout) == pdTRUE;
}

}  // namespace usb
