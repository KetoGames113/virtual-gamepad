# Virtual Gamepad Wire Protocol (v1)

Transport: **UDP**, single port **47998** on the PC, used for discovery, handshake,
input streaming and heartbeats. All multi-byte integers are **little-endian**.

Every packet starts with:

| Offset | Size | Field   | Value |
|--------|------|---------|-------|
| 0      | 1    | magic   | `0xA6` |
| 1      | 1    | type    | see below |

Packets with the wrong magic byte are silently dropped.

## Packet types

| Type | Name              | Direction       |
|------|-------------------|-----------------|
| 1    | INPUT             | phone -> PC     |
| 2    | HELLO             | phone -> PC     |
| 3    | HEARTBEAT         | phone -> PC     |
| 4    | DISCOVER          | phone -> PC (broadcast) |
| 5    | DISCOVER_RESPONSE | PC -> phone (unicast)   |
| 6    | HELLO_ACK         | PC -> phone     |
| 7    | GOODBYE           | phone -> PC     |
| 8    | ACTIVE_APP        | PC -> phone     |
| 9    | RUMBLE            | PC -> phone     |

### INPUT (type 1) — 18 bytes total

| Offset | Size | Field   | Notes |
|--------|------|---------|-------|
| 2      | 2    | buttons | bitmask, see below |
| 4      | 2    | LX      | int16, -32768..32767 |
| 6      | 2    | LY      | int16, -32768..32767 |
| 8      | 2    | RX      | int16, -32768..32767 |
| 10     | 2    | RY      | int16, -32768..32767 |
| 12     | 1    | LT      | uint8, 0..255 |
| 13     | 1    | RT      | uint8, 0..255 |
| 14     | 4    | seq     | uint32, incrementing counter |

Button bitmask (bit -> Xbox360 button):

```
0  A            8  Start
1  B            9  Back
2  X            10 Guide
3  Y            11 DPad Up
4  LB           12 DPad Down
5  RB           13 DPad Left
6  L-stick click 14 DPad Right
7  R-stick click 15 reserved
```

The app sends INPUT packets at ~60 Hz while connected (fixed-rate loop), not
only on change — this keeps the connection's liveness obvious and avoids
needing a separate keep-alive most of the time.

### HELLO (type 2)

| Offset | Size | Field        |
|--------|------|--------------|
| 2      | 1    | nameLen (n)  |
| 3      | n    | deviceName (UTF-8, e.g. "Sam's Pixel") |

Sent once when the phone connects. The PC creates a new virtual Xbox 360
controller (via ViGEmBus) for that phone's `IP:port` and replies with
HELLO_ACK.

### HELLO_ACK (type 6)

| Offset | Size | Field   |
|--------|------|---------|
| 2      | 1    | status  | `1` = OK / controller created, `0` = error (e.g. ViGEmBus missing) |

### HEARTBEAT (type 3)

Just the 2-byte header. Sent by the phone if no INPUT packet has gone out for
>500ms (e.g. app briefly backgrounded) so the PC doesn't time the client out.

### GOODBYE (type 7)

Just the 2-byte header. Sent when the phone disconnects cleanly so the PC can
immediately dispose of the virtual controller instead of waiting for timeout.

### ACTIVE_APP (type 8)

| Offset | Size | Field       |
|--------|------|-------------|
| 2      | 1    | nameLen (n) |
| 3      | n    | processName (UTF-8, foreground app's process name without `.exe`) |

Sent by the PC to every connected phone when the foreground application
changes, re-sent every ~3 s (UDP can drop packets) and once right after
HELLO_ACK. The phone may use it to switch layout profiles automatically.
The host's own window is never reported. Older apps ignore this packet.

### RUMBLE (type 9) — 4 bytes total

| Offset | Size | Field        |
|--------|------|--------------|
| 2      | 1    | largeMotor (0-255, heavy / low frequency)  |
| 3      | 1    | smallMotor (0-255, light / high frequency) |

Sent by the PC when a game sets rumble on the virtual Xbox 360 controller, and
re-sent every ~150 ms while either motor is non-zero (UDP can drop packets).
`0, 0` means stop. The phone also stops by itself if no RUMBLE packet arrives
for ~450 ms. Older apps ignore this packet.

### DISCOVER (type 4)

Just the 2-byte header, sent by the phone to the **broadcast address**
(`255.255.255.255:47998`) of its current WiFi subnet.

### DISCOVER_RESPONSE (type 5)

| Offset | Size | Field       |
|--------|------|-------------|
| 2      | 1    | nameLen (n) |
| 3      | n    | hostName (UTF-8, PC's machine name) |

Sent by the PC directly back to the sender's address so the phone can list
available PCs on the network instead of requiring manual IP entry (manual
entry remains available as a fallback, e.g. across subnets/VPNs).

## Timeouts

The PC drops a client (destroys its virtual controller) if no packet of any
type has been received from that `IP:port` for **3 seconds**.

## Bluetooth (planned, not yet implemented)

The same logical packet layout will be reused over an RFCOMM/L2CAP socket
once Bluetooth transport is added, so the app-side input model and the
PC-side `IInputTransport` abstraction don't need to change — only a new
transport implementation needs to be added on each side. Tracked in
`README.md` roadmap.
