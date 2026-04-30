#pragma once
#include <cstdint>
#include <span>

#include "FreeRTOS.h"
#include "queue.h"

namespace usb {

struct RxPacket {
    uint8_t data[64];
    uint32_t len;
};

// Send data over USB CDC. Blocks until the previous transfer completes,
// then initiates a new transfer. Returns false if data exceeds the TX buffer.
bool send(std::span<const uint8_t> data);

// Block until a USB RX packet arrives (or timeout elapses).
// Returns false on timeout.
bool rx_receive(RxPacket& pkt, TickType_t timeout = portMAX_DELAY);

}  // namespace usb
