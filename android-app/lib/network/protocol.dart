import 'dart:convert';
import 'dart:typed_data';

/// Wire protocol constants. Keep in sync with ../../../PROTOCOL.md and
/// windows-app/Protocol.cs.
class Protocol {
  static const int magic = 0xA6;
  static const int port = 47998;

  static const int typeInput = 1;
  static const int typeHello = 2;
  static const int typeHeartbeat = 3;
  static const int typeDiscover = 4;
  static const int typeDiscoverResponse = 5;
  static const int typeHelloAck = 6;
  static const int typeGoodbye = 7;
  static const int typeActiveApp = 8;
  static const int typeRumble = 9;

  static const int bitA = 0;
  static const int bitB = 1;
  static const int bitX = 2;
  static const int bitY = 3;
  static const int bitLb = 4;
  static const int bitRb = 5;
  static const int bitLsClick = 6;
  static const int bitRsClick = 7;
  static const int bitStart = 8;
  static const int bitBack = 9;
  static const int bitGuide = 10;
  static const int bitDpadUp = 11;
  static const int bitDpadDown = 12;
  static const int bitDpadLeft = 13;
  static const int bitDpadRight = 14;
}

/// Builds the raw byte packets sent to the PC.
class PacketBuilder {
  static Uint8List discover() {
    return Uint8List.fromList([Protocol.magic, Protocol.typeDiscover]);
  }

  static Uint8List hello(String deviceName) {
    final nameBytes = utf8.encode(deviceName);
    final len = nameBytes.length.clamp(0, 255);
    final packet = Uint8List(3 + len);
    packet[0] = Protocol.magic;
    packet[1] = Protocol.typeHello;
    packet[2] = len;
    packet.setRange(3, 3 + len, nameBytes);
    return packet;
  }

  static Uint8List heartbeat() {
    return Uint8List.fromList([Protocol.magic, Protocol.typeHeartbeat]);
  }

  static Uint8List goodbye() {
    return Uint8List.fromList([Protocol.magic, Protocol.typeGoodbye]);
  }

  /// Builds an 18-byte INPUT packet. Stick axes must be in [-1.0, 1.0],
  /// triggers in [0.0, 1.0].
  static Uint8List input({
    required int buttons,
    required double lx,
    required double ly,
    required double rx,
    required double ry,
    required double lt,
    required double rt,
    required int sequence,
  }) {
    final data = ByteData(18);
    data.setUint8(0, Protocol.magic);
    data.setUint8(1, Protocol.typeInput);
    data.setUint16(2, buttons & 0xFFFF, Endian.little);
    data.setInt16(4, _axisToInt16(lx), Endian.little);
    data.setInt16(6, _axisToInt16(ly), Endian.little);
    data.setInt16(8, _axisToInt16(rx), Endian.little);
    data.setInt16(10, _axisToInt16(ry), Endian.little);
    data.setUint8(12, _triggerToByte(lt));
    data.setUint8(13, _triggerToByte(rt));
    data.setUint32(14, sequence & 0xFFFFFFFF, Endian.little);
    return data.buffer.asUint8List();
  }

  static int _axisToInt16(double v) {
    final clamped = v.clamp(-1.0, 1.0);
    return (clamped * 32767).round();
  }

  static int _triggerToByte(double v) {
    final clamped = v.clamp(0.0, 1.0);
    return (clamped * 255).round();
  }
}

/// A DISCOVER_RESPONSE parsed from an incoming UDP datagram.
class DiscoveredHost {
  final String name;
  final String address;
  DiscoveredHost({required this.name, required this.address});
}

/// Parses an incoming datagram. Returns null if it's not a recognized
/// DISCOVER_RESPONSE or HELLO_ACK; [type] tells the caller which it was.
class ParsedReply {
  final int type;
  final String? hostName;
  final bool? helloOk;

  /// RUMBLE: motor speeds 0-255 (large = heavy/low-frequency, small = light).
  final int? rumbleLarge;
  final int? rumbleSmall;
  ParsedReply({
    required this.type,
    this.hostName,
    this.helloOk,
    this.rumbleLarge,
    this.rumbleSmall,
  });
}

ParsedReply? parseReply(Uint8List data) {
  if (data.length < 2 || data[0] != Protocol.magic) return null;
  final type = data[1];
  if (type == Protocol.typeDiscoverResponse || type == Protocol.typeActiveApp) {
    if (data.length < 3) return null;
    final nameLen = data[2];
    if (data.length < 3 + nameLen) return null;
    final name = utf8.decode(data.sublist(3, 3 + nameLen));
    return ParsedReply(type: type, hostName: name);
  }
  if (type == Protocol.typeRumble) {
    if (data.length < 4) return null;
    return ParsedReply(type: type, rumbleLarge: data[2], rumbleSmall: data[3]);
  }
  if (type == Protocol.typeHelloAck) {
    if (data.length < 3) return null;
    return ParsedReply(type: type, helloOk: data[2] == 1);
  }
  return null;
}
