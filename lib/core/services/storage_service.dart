import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transfer_models.dart';

class StorageService {
  static const _historyKey = 'wasla_history_v2';
  static const _legacyHistoryKey = 'wasla_history_v1';
  static const _deviceNameKey = 'wasla_device_name';
  static const _trustedKey = 'wasla_trusted_devices_v1';

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
    final raw = prefs.getStringList(_historyKey);
    if (raw == null) {
      final legacy = prefs.getStringList(_legacyHistoryKey) ?? const [];
      final migrated = _decodeRecords(legacy);
      if (migrated.isNotEmpty) {
        await _saveHistory(migrated);
        await prefs.remove(_legacyHistoryKey);
      }
      return migrated;
    }
    return _decodeRecords(raw);
  }

  Future<void> addHistory(TransferRecord record) async {
    final records = await history();
    records.insert(0, record);
    await _saveHistory(records.take(100).toList());
  }

  Future<void> deleteHistory(String id) async {
    final records = await history();
    await _saveHistory(records.where((e) => e.id != id).toList());
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove(_legacyHistoryKey);
  }

  Future<Set<String>> trustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_trustedKey) ?? const []).toSet();
  }

  Future<void> setTrusted(String id, bool trusted) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await trustedDevices();
    if (trusted) ids.add(id); else ids.remove(id);
    await prefs.setStringList(_trustedKey, ids.toList());
  }

  List<TransferRecord> _decodeRecords(List<String> raw) {
    final result = <TransferRecord>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) result.add(_fromJson(decoded));
      } catch (_) {}
    }
    return result;
  }

  TransferRecord _fromJson(Map<String, dynamic> j) {
    final directionName = j['direction'] as String? ?? TransferDirection.sent.name;
    final direction = TransferDirection.values.firstWhere((e) => e.name == directionName, orElse: () => TransferDirection.sent);
    return TransferRecord(
      id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      direction: direction,
      device: j['device'] as String? ?? 'جهاز غير معروف',
      totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      completedBytes: (j['completedBytes'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? TransferStatus.incomplete.name,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(j['endedAt'] as String? ?? ''),
      reason: j['reason'] as String?,
      averageSpeed: (j['averageSpeed'] as num?)?.toDouble() ?? 0,
      files: (j['files'] is List) ? (j['files'] as List).whereType<String>().toList() : const [],
      schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Future<void> _saveHistory(List<TransferRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, records.map((e) => jsonEncode({
      'schemaVersion': e.schemaVersion,
      'id': e.id,
      'direction': e.direction.name,
      'device': e.device,
      'totalBytes': e.totalBytes,
      'completedBytes': e.completedBytes,
      'status': e.status,
      'createdAt': e.createdAt.toIso8601String(),
      'endedAt': e.endedAt?.toIso8601String(),
      'reason': e.reason,
      'averageSpeed': e.averageSpeed,
      'files': e.files,
    })).toList());
  }
}
