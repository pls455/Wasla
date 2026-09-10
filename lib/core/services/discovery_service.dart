import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/transfer_models.dart';
import 'storage_service.dart';

class DiscoveryService {
  DiscoveryService(this.storage);
  final StorageService storage;
  static const discoveryPort = 45454;
  RawDatagramSocket? _socket;
  ServerSocket? _server;
  Timer? _timer;
  String? _id;
  final _devices = <String, NearbyDevice>{};
  final _stream = StreamController<List<NearbyDevice>>.broadcast();

  Stream<List<NearbyDevice>> get devices => _stream.stream;
  Future<ServerSocket?> get transferServer async => _server;

  Future<void> start() async {
    if (_socket != null) return;
    _id = '${DateTime.now().microsecondsSinceEpoch}-${Platform.localHostname}';
    final name = await storage.deviceName();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true, reusePort: true);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _socket!.receive();
      if (dg == null) return;
      try {
        final data = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (data['type'] != 'wasla_hello' || data['id'] == _id) return;
        _devices[data['id'] as String] = NearbyDevice(id: data['id'], name: data['name'] ?? 'جهاز قريب', host: dg.address.address, port: (data['port'] as num).toInt());
        _emit();
      } catch (_) {}
    });
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: true);
    _broadcast(name);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _broadcast(name));
  }

  void _broadcast(String name) {
    final socket = _socket;
    final server = _server;
    if (socket == null || server == null || _id == null) return;
    final bytes = utf8.encode(jsonEncode({'type': 'wasla_hello', 'id': _id, 'name': name, 'port': server.port, 'ts': DateTime.now().millisecondsSinceEpoch}));
    try { socket.send(bytes, InternetAddress('255.255.255.255'), discoveryPort); } catch (_) {}
  }

  Future<Socket?> connect(NearbyDevice device) async {
    try { return await Socket.connect(device.host, device.port, timeout: const Duration(seconds: 5)); } catch (_) { return null; }
  }

  void _emit() => _stream.add(_devices.values.toList()..sort((a, b) => a.name.compareTo(b.name)));

  Future<void> dispose() async {
    _timer?.cancel();
    _socket?.close();
    await _server?.close();
    await _stream.close();
  }
}
