import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/transfer_models.dart';
import 'storage_service.dart';

class DiscoveryService {
  DiscoveryService(this.storage);
  final StorageService storage;
  static const discoveryPort = 45454;
  static const ttl = Duration(seconds: 8);
  RawDatagramSocket? _socket;
  ServerSocket? _server;
  Timer? _timer;
  String? _id;
  String? _lastError;
  final _devices = <String, NearbyDevice>{};
  final _lastSeen = <String, DateTime>{};
  final _stream = StreamController<List<NearbyDevice>>.broadcast();
  Completer<ServerSocket>? _serverCompleter;
  bool _started = false;
  Stream<List<NearbyDevice>> get devices => _stream.stream;
  bool get isStarted => _started;
  String? get lastError => _lastError;
  int? get serverPort => _server?.port;
  Future<ServerSocket> get transferServer async {
    if (_server != null) return _server!;
    if (!_started) await start();
    final completer = _serverCompleter;
    if (completer == null) throw StateError('خادم النقل غير مهيأ');
    return completer.future;
  }
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _serverCompleter = Completer<ServerSocket>();
    try {
      _id = '${DateTime.now().microsecondsSinceEpoch}-${Platform.localHostname}';
      final name = await storage.deviceName();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true, reusePort: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket?.receive();
        if (dg != null) _handleDatagram(dg);
      }, onError: (Object error) => _lastError = 'خطأ في اكتشاف الأجهزة: $error');
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: true);
      if (!_serverCompleter!.isCompleted) _serverCompleter!.complete(_server);
      _broadcast(name);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) { _broadcast(name); _pruneExpired(); });
    } catch (error, stack) {
      _lastError = 'تعذر تشغيل خدمة الشبكة: $error';
      if (_serverCompleter != null && !_serverCompleter!.isCompleted) _serverCompleter!.completeError(error, stack);
      await _closeResources();
      _started = false;
      rethrow;
    }
  }
  void _handleDatagram(Datagram dg) {
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'wasla_hello') return;
      final id = decoded['id']; final name = decoded['name']; final port = decoded['port'];
      if (id is! String || id.isEmpty || id == _id || name is! String || port is! num) return;
      final safePort = port.toInt();
      if (safePort < 1 || safePort > 65535) return;
      final now = DateTime.now();
      _lastSeen[id] = now;
      _devices[id] = NearbyDevice(id: id, name: name.trim().isEmpty ? 'جهاز قريب' : name.trim(), host: dg.address.address, port: safePort, status: _devices[id]?.status ?? DeviceStatus.available, lastSeen: now);
      _emit();
    } catch (error) { _lastError = 'رسالة اكتشاف غير صالحة: $error'; }
  }
  void _broadcast(String name) {
    final socket = _socket; final server = _server;
    if (socket == null || server == null || _id == null) return;
    final bytes = utf8.encode(jsonEncode({'protocol': 2, 'type': 'wasla_hello', 'id': _id, 'name': name, 'port': server.port, 'ts': DateTime.now().millisecondsSinceEpoch}));
    if (bytes.length > 2048) return;
    try { socket.send(bytes, InternetAddress('255.255.255.255'), discoveryPort); } catch (error) { _lastError = 'تعذر إرسال اكتشاف الشبكة: $error'; }
  }
  void refresh() => _pruneExpired();
  Future<Socket?> connect(NearbyDevice device) async {
    if (device.blocked) return null;
    try { return await Socket.connect(device.host, device.port, timeout: const Duration(seconds: 5)); }
    on SocketException catch (error) { _lastError = 'تعذر الاتصال بـ ${device.name}: ${error.message}'; return null; }
    on TimeoutException { _lastError = 'انتهت مهلة الاتصال بـ ${device.name}'; return null; }
  }
  void _pruneExpired() {
    final now = DateTime.now();
    final expired = _lastSeen.entries.where((e) => now.difference(e.value) > ttl).map((e) => e.key).toList();
    for (final id in expired) { _lastSeen.remove(id); _devices.remove(id); }
    if (expired.isNotEmpty) _emit();
  }
  void _emit() { if (!_stream.isClosed) _stream.add(_devices.values.toList()..sort((a, b) => a.name.compareTo(b.name))); }
  Future<void> _closeResources() async { _timer?.cancel(); _timer = null; _socket?.close(); _socket = null; await _server?.close(); _server = null; }
  Future<void> dispose() async { await _closeResources(); if (!_stream.isClosed) await _stream.close(); }
}
