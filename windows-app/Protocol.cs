namespace VirtualGamepadHost;

/// <summary>
/// Constants and small helpers matching PROTOCOL.md. Keep this file in sync
/// with android-app/lib/network/protocol.dart if you ever change the wire
/// format.
/// </summary>
public static class Protocol
{
    public const byte Magic = 0xA6;
    public const int Port = 47998;

    public const byte TypeInput = 1;
    public const byte TypeHello = 2;
    public const byte TypeHeartbeat = 3;
    public const byte TypeDiscover = 4;
    public const byte TypeDiscoverResponse = 5;
    public const byte TypeHelloAck = 6;
    public const byte TypeGoodbye = 7;
    public const byte TypeActiveApp = 8;
    public const byte TypeRumble = 9;

    public const int ClientTimeoutMs = 3000;

    // Bit positions within the INPUT packet's 16-bit button mask.
    public const int BitA = 0;
    public const int BitB = 1;
    public const int BitX = 2;
    public const int BitY = 3;
    public const int BitLb = 4;
    public const int BitRb = 5;
    public const int BitLsClick = 6;
    public const int BitRsClick = 7;
    public const int BitStart = 8;
    public const int BitBack = 9;
    public const int BitGuide = 10;
    public const int BitDpadUp = 11;
    public const int BitDpadDown = 12;
    public const int BitDpadLeft = 13;
    public const int BitDpadRight = 14;
}

/// <summary>Parsed representation of an INPUT packet.</summary>
public readonly struct GamepadInputState
{
    public required ushort Buttons { get; init; }
    public required short Lx { get; init; }
    public required short Ly { get; init; }
    public required short Rx { get; init; }
    public required short Ry { get; init; }
    public required byte Lt { get; init; }
    public required byte Rt { get; init; }
    public required uint Sequence { get; init; }

    public bool Button(int bit) => (Buttons & (1 << bit)) != 0;
}
