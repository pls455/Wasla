import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

String bytesText(int bytes) {
  if (bytes < 1024) return '$bytes ب';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} م.ب';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ج.ب';
}

String speedText(double bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} م.ب/ث';

void main() => runApp(const WaslaApp());

class WaslaApp extends StatefulWidget {
  const WaslaApp({super.key});
  @override State<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends State<WaslaApp> {
  final storage = StorageService();
  late final DiscoveryService discovery = DiscoveryService(storage);
  bool dark = true;

  @override
  void initState() {
    super.initState();
    discovery.start();
  }

  @override
  void dispose() {
    discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C4DFF),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وصلة',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(
          storage: storage,
          discovery: discovery,
          dark: dark,
          onTheme: () => setState(() => dark = !dark),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.storage, required this.discovery, required this.dark, required this.onTheme});
  final StorageService storage;
  final DiscoveryService discovery;
  final bool dark;
  final VoidCallback onTheme;
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final receiver = ReceiveCoordinator();
  List<NearbyDevice> devices = const [];
  StreamSubscription<List<NearbyDevice>>? sub;
  bool receiving = true;

  @override
  void initState() {
    super.initState();
    sub = widget.discovery.devices.listen((v) {
      if (mounted) setState(() => devices = v);
    });
    _startReceiver();
  }

  Future<void> _startReceiver() async {
    await receiver.start(
      context: context,
      storage: widget.storage,
      discovery: widget.discovery,
      enabled: () => receiving,
    );
  }

  @override
  void dispose() {
    sub?.cancel();
    receiver.stop();
    super.dispose();
  }

  Future<List<TransferFile>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) return const [];
    final files = <TransferFile>[];
    for (final item in result.files) {
      final path = item.path;
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) {
        files.add(TransferFile(name: item.name, path: path, size: file.lengthSync()));
      }
    }
    return files;
  }

  Future<void> sendFiles({NearbyDevice? device}) async {
    final files = await pickFiles();
    if (!mounted || files.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendPage(
          storage: widget.storage,
          discovery: widget.discovery,
          files: files,
          devices: devices,
          selected: device,
        ),
      ),
    );
  }

  void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('وصلة', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          const Text('انقلها ببساطة.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.05)),
          const SizedBox(height: 7),
          Text('خطوتان فقط: اختر ما تريد، ثم اختر الجهاز.', style: TextStyle(color: c.onSurfaceVariant, fontSize: 16)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _ActionCard(icon: Icons.arrow_upward_rounded, title: 'إرسال', subtitle: 'اختيار الملفات', color: c.primary, onTap: sendFiles)),
            const SizedBox(width: 12),
            Expanded(child: _ActionCard(icon: Icons.arrow_downward_rounded, title: 'استقبال', subtitle: receiving ? 'مفعّل الآن' : 'متوقف', color: c.secondary, onTap: () => setState(() => receiving = !receiving))),
          ]),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              value: receiving,
              onChanged: (v) => setState(() => receiving = v),
              secondary: Icon(receiving ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: receiving ? c.primary : c.error),
              title: Text(receiving ? 'الاستقبال جاهز' : 'الاستقبال متوقف', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(receiving ? 'يمكن لجهاز آخر إرسال الملفات إليك.' : 'فعّل الاستقبال قبل أن يرسل لك جهاز آخر.'),
            ),
          ),
          const SizedBox(height: 22),
          Row(children: [const Text('الأجهزة القريبة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const Spacer(), Text('${devices.length}', style: TextStyle(color: c.primary, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 10),
          if (devices.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
              Icon(Icons.devices_other_rounded, size: 44, color: c.onSurfaceVariant),
              const SizedBox(height: 8),
              const Text('لا يوجد جهاز قريب حالياً', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('افتح وصلة على الجهاز الآخر، فعّل الاستقبال، وتأكد أن الجهازين على نفس الشبكة.', textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
            ])))
          else
            ...devices.map((d) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: c.primaryContainer, child: Icon(Icons.phone_android_rounded, color: c.onPrimaryContainer)),
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('جاهز • ${d.host}'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => sendFiles(device: d),
              ),
            )),
          const SizedBox(height: 18),
          const Text('أدوات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Tool(icon: Icons.qr_code_scanner_rounded, label: 'مسح QR', onTap: () => open(ScanPage(storage: widget.storage, discovery: widget.discovery)))),
            const SizedBox(width: 8),
            Expanded(child: _Tool(icon: Icons.qr_code_rounded, label: 'عرض QR', onTap: () => open(QrPage(storage: widget.storage, discovery: widget.discovery)))),
            const SizedBox(width: 8),
            Expanded(child: _Tool(icon: Icons.history_rounded, label: 'السجل', onTap: () => open(HistoryPage(storage: widget.storage)))),
            const SizedBox(width: 8),
            Expanded(child: _Tool(icon: Icons.settings_rounded, label: 'الإعدادات', onTap: () => open(SettingsPage(storage: widget.storage)))),
          ]),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 50, height: 50, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: Theme.of(context).colorScheme.onPrimary)),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ),
  );
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 3), child: Column(children: [Icon(icon), const SizedBox(height: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center)]))));
}

class ReceiveCoordinator {
  ServerSocket? server;
  bool running = false;
  BuildContext? context;
  StorageService? storage;
  Future<void> start({required BuildContext context, required StorageService storage, required DiscoveryService discovery, required bool Function() enabled}) async {
    if (running) return;
    this.context = context;
    this.storage = storage;
    try {
      server = await discovery.transferServer;
      running = true;
      _listen(enabled);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل الاستقبال: $e')));
    }
  }

  Future<void> _listen(bool Function() enabled) async {
    final s = server;
    if (s == null) return;
    await for (final socket in s) {
      if (!running) { socket.destroy(); break; }
      if (!enabled()) { socket.destroy(); continue; }
      await _handle(socket);
    }
  }

  Future<void> _handle(Socket socket) async {
    try {
      final reader = SocketReader(socket);
      final offer = await reader.readLine();
      if (offer['type'] != 'offer') throw StateError('طلب اتصال غير صالح');
      final raw = offer['files'];
      if (raw is! List) throw StateError('بيانات الملفات غير صالحة');
      final files = <TransferFile>[];
      for (final item in raw) {
        final m = Map<String, dynamic>.from(item as Map);
        files.add(TransferFile(name: m['name'] as String, path: '', size: (m['size'] as num).toInt(), hash: m['hash'] as String?));
      }
      final total = files.fold<int>(0, (a, b) => a + b.size);
      final accepted = await _confirm(offer['sender'] as String? ?? 'جهاز', files.length, total, offer['code'] as String? ?? '------');
      if (!accepted) {
        socket.write('${jsonEncode({'type': 'reject', 'session': offer['session']})}\n');
        await socket.flush();
        return;
      }
      await TransferService(storage!).receive(
        socket: socket,
        files: files,
        reader: reader,
        sessionId: offer['session'] as String?,
        onProgress: (_) {},
      );
      if (context != null && context!.mounted) {
        ScaffoldMessenger.of(context!).showSnackBar(SnackBar(content: Text('اكتمل استقبال ${files.length} عنصر')));
      }
    } catch (e) {
      if (context != null && context!.mounted) {
        ScaffoldMessenger.of(context!).showSnackBar(SnackBar(content: Text('فشل الاستقبال: ${e.toString().replaceFirst('Bad state: ', '')}')));
      }
    } finally {
      socket.destroy();
    }
  }

  Future<bool> _confirm(String sender, int count, int total, String code) async {
    final c = context;
    if (c == null || !c.mounted) return false;
    return await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب استقبال'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$sender يريد إرسال $count عنصر.'),
          const SizedBox(height: 8),
          Text('الحجم: ${bytesText(total)}'),
          const SizedBox(height: 14),
          Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Text('رمز التحقق\n$code', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استقبال')),
        ],
      ),
    ) ?? false;
  }

  void stop() {
    running = false;
    server?.close();
    server = null;
  }
}

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.storage, required this.discovery, required this.files, required this.devices, this.selected});
  final StorageService storage;
  final DiscoveryService discovery;
  final List<TransferFile> files;
  final List<NearbyDevice> devices;
  final NearbyDevice? selected;
  @override State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late NearbyDevice? selected = widget.selected;
  late List<NearbyDevice> devices = widget.devices;
  StreamSubscription<List<NearbyDevice>>? sub;
  TransferProgress? progress;
  String message = '';
  bool sending = false;

  @override
  void initState() {
    super.initState();
    sub = widget.discovery.devices.listen((v) {
      if (mounted) setState(() => devices = v);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> send() async {
    final target = selected;
    if (target == null || sending) return;
    setState(() { sending = true; message = ''; });
    final socket = await widget.discovery.connect(target);
    if (socket == null) {
      if (mounted) setState(() { sending = false; message = 'تعذر الاتصال. تأكد أن الاستقبال مفعّل على الجهاز الآخر.'; });
      return;
    }
    try {
      final sender = await widget.storage.deviceName();
      await TransferService(widget.storage).send(
        socket: socket,
        senderName: sender,
        files: widget.files,
        onProgress: (p) { if (mounted) setState(() => progress = p); },
      );
      if (mounted) setState(() { sending = false; message = 'تم الإرسال والتحقق بنجاح ✓'; });
    } catch (e) {
      if (mounted) setState(() { sending = false; message = 'لم يكتمل الإرسال: ${e.toString().replaceFirst('Bad state: ', '')}'; });
    } finally {
      socket.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final total = widget.files.fold<int>(0, (a, b) => a + b.size);
    final p = progress;
    final fraction = p == null || p.total == 0 ? 0.0 : (p.bytes / p.total).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        _Step(number: 1, title: 'الملفات', subtitle: '${widget.files.length} عنصر • ${bytesText(total)}'),
        Card(child: Column(children: [
          ...widget.files.take(8).map((f) => ListTile(leading: const Icon(Icons.insert_drive_file_rounded), title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(bytesText(f.size)))),
          if (widget.files.length > 8) Padding(padding: const EdgeInsets.all(12), child: Text('+ ${widget.files.length - 8} عناصر أخرى')),
        ])),
        const SizedBox(height: 18),
        _Step(number: 2, title: 'الجهاز المستلم', subtitle: selected == null ? 'اختر جهازاً' : 'تم اختيار ${selected!.name}'),
        if (devices.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد أجهزة. افتح وصلة على الجهاز الآخر وفعّل الاستقبال.', textAlign: TextAlign.center)))
        else
          ...devices.map((d) => Card(
            color: selected?.id == d.id ? c.primaryContainer : null,
            child: ListTile(
              onTap: sending ? null : () => setState(() => selected = d),
              leading: Icon(selected?.id == d.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(d.host),
              trailing: selected?.id == d.id ? const Icon(Icons.check_circle_rounded) : null,
            ),
          )),
        const SizedBox(height: 18),
        if (p != null) ...[
          LinearProgressIndicator(value: fraction, minHeight: 9, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 8),
          Text('${(fraction * 100).toStringAsFixed(0)}% • ${speedText(p.speed)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
        ],
        if (message.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: message.contains('بنجاح') ? c.primary : c.error, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: selected == null || sending ? null : send, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'جاري الإرسال...' : 'إرسال الآن')),
        if (selected == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('لن يبدأ الإرسال حتى تختار جهازاً.', textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.subtitle});
  final int number;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(children: [CircleAvatar(radius: 15, child: Text('$number')), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]))]));
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.storage, required this.discovery});
  final StorageService storage;
  final DiscoveryService discovery;
  @override State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String message = 'وجّه الكاميرا نحو QR الخاص بوصلة';
  bool handled = false;

  void detect(BarcodeCapture capture) {
    if (handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || !raw.startsWith('WASLA:')) continue;
      try {
        final data = jsonDecode(raw.substring(6)) as Map<String, dynamic>;
        final host = data['host'] as String?;
        final port = (data['port'] as num?)?.toInt();
        if (host == null || port == null || port < 1 || port > 65535) throw const FormatException();
        handled = true;
        final device = NearbyDevice(id: 'qr-$host-$port', name: data['name'] as String? ?? 'جهاز قريب', host: host, port: port);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QrTargetPage(storage: widget.storage, discovery: widget.discovery, target: device)));
        return;
      } catch (_) {
        if (mounted) setState(() => message = 'رمز QR غير صالح');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مسح QR')),
    body: Stack(children: [
      MobileScanner(
        onDetect: detect,
        errorBuilder: (context, error, child) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_rounded, size: 58),
          const SizedBox(height: 12),
          const Text('تعذر تشغيل الكاميرا', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('تأكد من منح وصلة صلاحية الكاميرا من إعدادات أندرويد.', textAlign: TextAlign.center),
        ]))),
      ),
      Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Container(margin: const EdgeInsets.all(18), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .75), borderRadius: BorderRadius.circular(16)), child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), textAlign: TextAlign.center)))),
    ]),
  );
}

class QrTargetPage extends StatelessWidget {
  const QrTargetPage({super.key, required this.storage, required this.discovery, required this.target});
  final StorageService storage;
  final DiscoveryService discovery;
  final NearbyDevice target;

  Future<void> choose(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null || !context.mounted) return;
    final files = <TransferFile>[];
    for (final item in result.files) {
      if (item.path == null) continue;
      final file = File(item.path!);
      if (file.existsSync()) files.add(TransferFile(name: item.name, path: item.path!, size: file.lengthSync()));
    }
    if (!context.mounted || files.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: storage, discovery: discovery, files: files, devices: [target], selected: target)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الجهاز من QR')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.check_circle_rounded, size: 64),
    const SizedBox(height: 12),
    Text(target.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
    Text('${target.host}:${target.port}'),
    const SizedBox(height: 22),
    FilledButton.icon(onPressed: () => choose(context), icon: const Icon(Icons.folder_open_rounded), label: const Text('اختيار الملفات وإرسال')),
  ]))));
}

class QrPage extends StatefulWidget {
  const QrPage({super.key, required this.storage, required this.discovery});
  final StorageService storage;
  final DiscoveryService discovery;
  @override State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  String payload = '';

  @override
  void initState() {
    super.initState();
    makeQr();
  }

  Future<void> makeQr() async {
    try {
      final name = await widget.storage.deviceName();
      final server = await widget.discovery.transferServer;
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      String ip = '';
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.address != '0.0.0.0') { ip = address.address; break; }
        }
        if (ip.isNotEmpty) break;
      }
      if (mounted) setState(() => payload = jsonEncode({'v': 1, 'host': ip, 'port': server.port, 'name': name}));
    } catch (e) {
      if (mounted) setState(() => payload = '');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('QR للاتصال')), body: Center(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
    const Text('على الجهاز الآخر افتح «مسح QR».', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    const SizedBox(height: 18),
    if (payload.isNotEmpty) Center(child: QrImageView(data: 'WASLA:$payload', size: 270, backgroundColor: Colors.white, padding: const EdgeInsets.all(16))) else const Center(child: CircularProgressIndicator()),
    const SizedBox(height: 12),
    if (payload.isNotEmpty) SelectableText(payload, textAlign: TextAlign.center),
  ])));
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.storage});
  final StorageService storage;
  @override State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<TransferRecord> records = const [];
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { final r = await widget.storage.history(); if (mounted) setState(() => records = r); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('السجل')), body: records.isEmpty ? const Center(child: Text('لا توجد عمليات نقل بعد.')) : ListView.builder(padding: const EdgeInsets.all(14), itemCount: records.length, itemBuilder: (_, i) { final r = records[i]; return Card(child: ListTile(leading: Icon(r.direction == TransferDirection.sent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded), title: Text(r.device, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${bytesText(r.completedBytes)} • ${r.status}\n${r.createdAt.toLocal()}'), isThreeLine: true)); }));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.storage});
  final StorageService storage;
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final controller = TextEditingController();
  @override void initState() { super.initState(); widget.storage.deviceName().then((v) { if (mounted) controller.text = v; }); }
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: ListView(padding: const EdgeInsets.all(20), children: [
    TextField(controller: controller, decoration: const InputDecoration(labelText: 'اسم الجهاز', prefixIcon: Icon(Icons.phone_android_rounded))),
    const SizedBox(height: 14),
    FilledButton(onPressed: () async { await widget.storage.setDeviceName(controller.text.trim().isEmpty ? 'هاتف وصلة' : controller.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اسم الجهاز'))); }, child: const Text('حفظ')),
    const SizedBox(height: 20),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('وصلة تنقل الملفات داخل الشبكة المحلية مباشرة، بدون حساب أو خادم وسيط.'))),
  ]));
}
