#pragma once
#include <cstdint>

namespace proto {

enum class MsgType : uint8_t {
    Heartbeat = 0x01,
};

// All message structs are packed — no padding between fields.
// Frame wire format: COBS( [type:u8] [payload:N bytes] [crc16_le:2 bytes] ) + 0x00

struct [[gnu::packed]] MsgHeartbeat {
    uint32_t seq;
};

}  // namespace proto
