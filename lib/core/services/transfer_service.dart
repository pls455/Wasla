import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/transfer_models.dart';
import 'storage_service.dart';

class TransferProgress {
  const TransferProgress({required this.bytes, required this.total, required this.speed, required this.eta, required this.status});
  final int bytes, total;
  final double speed;
  final Duration? eta;
  final String status;
}

class SocketReader {
  SocketReader(this.socket) : _iterator = StreamIterator<List<int>>(socket);
  final Socket socket;
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];
  bool _ended = false;

  Future<void> _fill() async {
    if (_ended || !await _iterator.moveNext()) {
      _ended = true;
      throw StateError('انقطع الاتصال');
    }
    _buffer.addAll(_iterator.current);
  }

  Future<List<int>> readExact(int count) async {
    while (_buffer.length < count) await _fill();
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }

  Future<Map<String, dynamic>> readLine() async {
    while (true) {
      final i = _buffer.indexOf(10);
      if (i >= 0) {
        final bytes = _buffer.sublist(0, i);
        _buffer.removeRange(0, i + 1);
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
      await _fill();
    }
  }
}

class TransferService {
  TransferService(this.storage);
  final StorageService storage;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<String> hashFile(String path) async {
    final collector = _DigestCollector();
    final sink = sha256.startChunkedConversion(collector);
    await for (final chunk in File(path).openRead()) { sink.add(chunk); }
    sink.close();
    return collector.digest;
  }

  Future<void> send({required Socket socket, required String senderName, required List<TransferFile> files, required void Function(TransferProgress) onProgress}) async {
    _cancelled = false;
    final reader = SocketReader(socket);
    final prepared = <TransferFile>[];
    for (final f in files) prepared.add(TransferFile(name: f.name, path: f.path, size: f.size, hash: await hashFile(f.path)));
    await _line(socket, {'type': 'offer', 'session': '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(999999)}', 'sender': senderName, 'files': prepared.map((f) => {'name': f.name, 'size': f.size, 'hash': f.hash}).toList()});
    final accepted = await reader.readLine();
    if (accepted['type'] != 'accept') throw StateError('لم يتم قبول النقل');
    final total = prepared.fold<int>(0, (a, b) => a + b.size);
    var done = 0;
    final started = DateTime.now();
    for (var i = 0; i < prepared.length; i++) {
      if (_cancelled) throw StateError('تم إلغاء النقل');
      final f = prepared[i];
      final offsets = accepted['offsets'] as List? ?? const [];
      final offset = min(i < offsets.length ? (offsets[i] as num).toInt() : 0, f.size);
      await _line(socket, {'type': 'file', 'index': i, 'name': f.name, 'size': f.size, 'hash': f.hash, 'offset': offset});
      final file = File(f.path).openSync();
      file.setPositionSync(offset);
      var sent = offset;
      done += offset;
      try {
        while (sent < f.size) {
          if (_cancelled) throw StateError('تم إلغاء النقل');
          final bytes = file.readSync(min(_chunkSize(done, started), f.size - sent));
          if (bytes.isEmpty) throw StateError('تعذر قراءة الملف');
          socket.add(bytes);
          // لا نعمل flush لكل قطعة. Socket buffers تجمع البيانات أصلًا، وawait لكل 256KB يضيف overhead واضحًا.
          sent += bytes.length;
          done += bytes.length;
          onProgress(_progress(done, total, started, 'جاري الإرسال'));
        }
      } finally { file.close(); }
      await _line(socket, {'type': 'file_end', 'index': i});
      if ((await reader.readLine())['type'] != 'verified') throw StateError('فشل التحقق من ${f.name}');
    }
    await _line(socket, {'type': 'done'});
    onProgress(_progress(total, total, started, 'اكتمل النقل والتحقق'));
  }

  Future<void> receive({required Socket socket, required List<TransferFile> files, required void Function(TransferProgress) onProgress, SocketReader? reader}) async {
    _cancelled = false;
    final input = reader ?? SocketReader(socket);
    final base = await storage.receiveDirectory();
    final total = files.fold<int>(0, (a, b) => a + b.size);
    var done = 0;
    final started = DateTime.now();
    final offsets = <int>[];
    for (final f in files) {
      final target = _target(base, _safe(f.name));
      final part = File('${target.path}.part');
      offsets.add(part.existsSync() ? await part.length() : 0);
    }
    await _line(socket, {'type': 'accept', 'offsets': offsets});
    for (var i = 0; i < files.length; i++) {
      final h = await input.readLine();
      if (h['type'] != 'file') throw StateError('بيانات نقل غير صالحة');
      final size = (h['size'] as num).toInt();
      final offset = min((h['offset'] as num?)?.toInt() ?? 0, size);
      final target = _target(base, _safe(h['name'] as String));
      final part = File('${target.path}.part');
      final existing = part.existsSync() ? await part.length() : 0;
      if (existing != offset) {
        if (part.existsSync()) await part.delete();
        if (offset != 0) throw StateError('نقطة الاستئناف غير متطابقة');
      }
      final file = part.openSync(mode: FileMode.append);
      var received = offset;
      done += offset;
      try {
        while (received < size) {
          if (_cancelled) throw StateError('تم إلغاء النقل');
          final bytes = await input.readExact(min(1024 * 1024, size - received));
          file.writeFromSync(bytes);
          received += bytes.length;
          done += bytes.length;
          onProgress(_progress(done, total, started, 'جاري الاستقبال'));
        }
      } finally { file.close(); }
      if ((await input.readLine())['type'] != 'file_end') throw StateError('نهاية ملف غير متوقعة');
      if (await hashFile(part.path) != h['hash']) throw StateError('فشل التحقق من سلامة ${files[i].name}');
      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
      await _line(socket, {'type': 'verified', 'index': i});
    }
    await input.readLine();
    onProgress(_progress(total, total, started, 'اكتمل الاستقبال والتحقق'));
  }

  TransferProgress _progress(int done, int total, DateTime started, String status) {
    final speed = done / max(0.001, DateTime.now().difference(started).inMilliseconds / 1000);
    return TransferProgress(bytes: done, total: total, speed: speed, eta: speed > 0 ? Duration(milliseconds: ((total - done) / speed * 1000).round()) : null, status: status);
  }

  int _chunkSize(int bytes, DateTime started) {
    if (bytes < 2 * 1024 * 1024) return 512 * 1024;
    final speed = bytes / max(0.001, DateTime.now().difference(started).inMilliseconds / 1000);
    if (speed > 30 * 1024 * 1024) return 1024 * 1024;
    if (speed > 10 * 1024 * 1024) return 1024 * 1024;
    return 512 * 1024;
  }

  File _target(Directory base, String name) {
    final original = File('${base.path}${Platform.pathSeparator}$name');
    if (!original.existsSync() && !File('${original.path}.part').existsSync()) return original;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot) : '';
    final stem = ext.isEmpty ? name : name.substring(0, name.length - ext.length);
    var i = 1;
    while (File('${base.path}${Platform.pathSeparator}$stem ($i)$ext').existsSync() || File('${base.path}${Platform.pathSeparator}$stem ($i)$ext.part').existsSync()) i++;
    return File('${base.path}${Platform.pathSeparator}$stem ($i)$ext');
  }

  String _safe(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim().isEmpty ? 'file' : name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  Future<void> _line(Socket socket, Map<String, dynamic> data) async { socket.write('${jsonEncode(data)}\n'); await socket.flush(); }
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;
  String get digest => value?.toString() ?? '';
  @override void add(Digest data) => value = data;
  @override void close() {}
}
