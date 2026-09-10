enum DeviceStatus { available, connecting, connected }

enum TransferDirection { sent, received }

class NearbyDevice {
  const NearbyDevice({required this.id, required this.name, required this.host, required this.port, this.status = DeviceStatus.available});
  final String id;
  final String name;
  final String host;
  final int port;
  final DeviceStatus status;
}

class TransferFile {
  const TransferFile({required this.name, required this.path, required this.size, this.hash});
  final String name;
  final String path;
  final int size;
  final String? hash;
}

class TransferRecord {
  const TransferRecord({required this.id, required this.direction, required this.device, required this.totalBytes, required this.completedBytes, required this.status, required this.createdAt});
  final String id;
  final TransferDirection direction;
  final String device;
  final int totalBytes;
  final int completedBytes;
  final String status;
  final DateTime createdAt;
}
