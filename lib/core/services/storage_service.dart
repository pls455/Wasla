import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transfer_models.dart';

class StorageService {
  static const _historyKey = 'wasla_history_v1';
  static const _deviceNameKey = 'wasla_device_name';

  Future<Directory> receiveDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}Wasla${Platform.pathSeparator}Received');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> deviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceNameKey) ?? 'هاتف وصلة';
  }

  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, name.trim().isEmpty ? 'هاتف وصلة' : name.trim());
  }

  Future<List<TransferRecord>> history() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? const [];
    return raw.map((e) {
      final j = jsonDecode(e) as Map<String, dynamic>;
      return TransferRecord(id: j['id'], direction: TransferDirection.values.byName(j['direction']), device: j['device'], totalBytes: j['totalBytes'], completedBytes: j['completedBytes'], status: j['status'], createdAt: DateTime.parse(j['createdAt']));
    }).toList();
  }

  Future<void> addHistory(TransferRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await history();
    records.insert(0, record);
    await prefs.setStringList(_historyKey, records.take(100).map((e) => jsonEncode({'id': e.id, 'direction': e.direction.name, 'device': e.device, 'totalBytes': e.totalBytes, 'completedBytes': e.completedBytes, 'status': e.status, 'createdAt': e.createdAt.toIso8601String()})).toList());
  }

  Future<void> clearHistory() async => (await SharedPreferences.getInstance()).remove(_historyKey);
}
