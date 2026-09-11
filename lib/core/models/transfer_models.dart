enum DeviceStatus { available, connecting, connected, unavailable }

enum TransferDirection { sent, received }

enum TransferStatus { success, failed, cancelled, rejected, paused, incomplete, resumed }

class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.status = DeviceStatus.available,
    this.lastSeen,
    this.deviceType = 'Android',
    this.trusted = false,
    this.blocked = false,
  });
  final String id;
  final String name;
  final String host;
  final int port;
  final DeviceStatus status;
  final DateTime? lastSeen;
  final String deviceType;
  final bool trusted;
  final bool blocked;
}

class TransferFile {
  const TransferFile({required this.name, required this.path, required this.size, this.hash});
  final String name;
  final String path;
  final int size;
  final String? hash;
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.device,
    required this.totalBytes,
    required this.completedBytes,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.reason,
    this.averageSpeed = 0,
    this.files = const [],
    this.schemaVersion = 2,
  });
  final String id;
  final TransferDirection direction;
  final String device;
  final int totalBytes;
  final int completedBytes;
  final String status;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String? reason;
  final double averageSpeed;
  final List<String> files;
  final int schemaVersion;
}
