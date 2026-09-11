import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

const appsChannel = MethodChannel('com.wasla/apps');

String bytesText(int bytes) {
  if (bytes < 1024) return '$bytes ب';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ج.ب';
}

String speedText(double bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب/ث';

Future<List<AppItem>> installedApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await appsChannel.invokeMethod<List<dynamic>>('listApps') ?? const [];
  return raw.map((e) => AppItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
}

Future<String?> exportApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return appsChannel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

class AppItem {
  const AppItem({required this.packageName, required this.name, required this.size, this.icon});
  final String packageName, name;
  final int size;
  final String? icon;
  factory AppItem.fromMap(Map<String, dynamic> m) => AppItem(
    packageName: m['packageName'] as String? ?? '',
    name: m['name'] as String? ?? 'تطبيق',
    size: (m['size'] as num?)?.toInt() ?? 0,
    icon: m['icon'] as String?,
  );
}

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
  void initState() { super.initState(); discovery.start(); }
  @override
  void dispose() { discovery.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6C4DFF), brightness: dark ? Brightness.dark : Brightness.light);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وصلة',
      theme: ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface, cardTheme: const CardThemeData(margin: EdgeInsets.zero)),
      home: Directionality(textDirection: TextDirection.rtl, child: HomePage(storage: storage, discovery: discovery, dark: dark, onTheme: () => setState(() => dark = !dark))),
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
  final receive = ReceiveCoordinator();
  List<NearbyDevice> devices = const [];
  StreamSubscription<List<NearbyDevice>>? devicesSub;
  String name = 'هاتف وصلة';
  bool receiveEnabled = true;
  @override
  void initState() {
    super.initState();
    devicesSub = widget.discovery.devices.listen((v) { if (mounted) setState(() => devices = v); });
    _init();
  }
  Future<void> _init() async {
    name = await widget.storage.deviceName();
    if (mounted) setState(() {});
    await receive.start(context: context, storage: widget.storage, discovery: widget.discovery, enabled: () => receiveEnabled);
  }
  @override
  void dispose() { devicesSub?.cancel(); receive.stop(); super.dispose(); }

  Future<List<TransferFile>> chooseFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) return const [];
    final out = <TransferFile>[];
    for (final item in result.files) {
      final path = item.path;
      if (path == null) continue;
      final f = File(path);
      if (f.existsSync()) out.add(TransferFile(name: item.name, path: path, size: f.lengthSync()));
    }
    return out;
  }

  Future<void> startSend() async {
    final files = await chooseFiles();
    if (!mounted || files.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SendFlow(storage: widget.storage, discovery: widget.discovery, files: files, initialDevices: devices)));
  }

  void page(Widget child) => Navigator.push(context, MaterialPageRoute(builder: (_) => child));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.link_rounded, color: c.onPrimary)),
          const SizedBox(width: 10),
          const Text('وصلة', style: TextStyle(fontWeight: FontWeight.w900)),
        ]),
        actions: [IconButton(onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
        const Text('انقلها ببساطة.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.05)),
        const SizedBox(height: 6),
        Text('اختر ماذا تريد، والباقي تتكفل به وصلة.', style: TextStyle(color: c.onSurfaceVariant, fontSize: 16)),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: ModeCard(icon: Icons.arrow_upward_rounded, title: 'إرسال', subtitle: 'اختر الملفات ثم الجهاز', color: c.primary, onTap: startSend)),
          const SizedBox(width: 12),
          Expanded(child: ModeCard(icon: Icons.arrow_downward_rounded, title: 'استقبال', subtitle: receiveEnabled ? 'جاهز لاستقبال الملفات' : 'متوقف مؤقتاً', color: c.secondary, onTap: () => setState(() => receiveEnabled = !receiveEnabled))),
        ]),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Icon(receiveEnabled ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: receiveEnabled ? c.primary : c.error),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(receiveEnabled ? 'الاستقبال مفعّل' : 'الاستقبال متوقف', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(receiveEnabled ? 'يمكن لجهاز آخر إرسال الملفات إليك الآن.' : 'فعّل الاستقبال حتى يستطيع جهاز آخر الاتصال.', style: TextStyle(color: c.onSurfaceVariant)),
          ])),
          Switch(value: receiveEnabled, onChanged: (v) async { setState(() => receiveEnabled = v); }),
        ]))),
        const SizedBox(height: 22),
        Row(children: [const Text('الأجهزة القريبة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const Spacer(), Text('${devices.length}', style: TextStyle(color: c.primary, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 10),
        if (devices.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          Icon(Icons.devices_other_rounded, size: 44, color: c.onSurfaceVariant),
          const SizedBox(height: 8),
          const Text('لا يوجد جهاز قريب حالياً', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('تأكد أن الجهازين على نفس الشبكة وأن وصلة مفتوحة على الجهاز الآخر.', textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
        ]))) else ...devices.map((d) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: CircleAvatar(backgroundColor: c.primaryContainer, child: Icon(Icons.phone_android_rounded, color: c.onPrimaryContainer)),
          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('متاح • ${d.host}'),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () async {
            final files = await chooseFiles();
            if (!mounted || files.isEmpty) return;
            page(SendFlow(storage: widget.storage, discovery: widget.discovery, files: files, initialDevices: devices, selected: d));
          },
        ))),
        const SizedBox(height: 18),
        const Text('طرق أخرى', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ToolTile(icon: Icons.qr_code_scanner_rounded, label: 'مسح QR', onTap: () => page(ScanPage(storage: widget.storage, discovery: widget.discovery)))),
          const SizedBox(width: 8),
          Expanded(child: ToolTile(icon: Icons.qr_code_rounded, label: 'عرض QR', onTap: () => page(QrPage(storage: widget.storage, discovery: widget.discovery)))),
          const SizedBox(width: 8),
          Expanded(child: ToolTile(icon: Icons.link_rounded, label: 'اتصال يدوي', onTap: () => page(ManualPage(storage: widget.storage, discovery: widget.discovery)))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ToolTile(icon: Icons.apps_rounded, label: 'التطبيقات', onTap: () => page(AppPage(storage: widget.storage, discovery: widget.discovery)))),
          const SizedBox(width: 8),
          Expanded(child: ToolTile(icon: Icons.history_rounded, label: 'السجل', onTap: () => page(HistoryPage(storage: widget.storage)))),
          const SizedBox(width: 8),
          Expanded(child: ToolTile(icon: Icons.settings_rounded, label: 'الإعدادات', onTap: () => page(SettingsPage(storage: widget.storage)))),
        ]),
      ]),
    );
  }
}

class ModeCard extends StatelessWidget {
  const ModeCard({super.key, required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon; final String title, subtitle; final Color color; final VoidCallback onTap;
  @override Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 50, height: 50, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: Theme.of(context).colorScheme.onPrimary)),
    const SizedBox(height: 14), Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]))));
}

class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5), child: Column(children: [Icon(icon), const SizedBox(height: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.center)]))));
}

class ReceiveCoordinator {
  ServerSocket? server;
  bool running = false;
  BuildContext? context;
  StorageService? storage;
  DiscoveryService? discovery;
  Future<void> start({required BuildContext context, required StorageService storage, required DiscoveryService discovery, required bool Function() enabled}) async {
    if (running) return;
    this.context = context; this.storage = storage; this.discovery = discovery;
    try { server = await discovery.transferServer; running = true; _loop(enabled); } catch (_) {}
  }
  Future<void> _loop(bool Function() enabled) async {
    final s = server; if (s == null) return;
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
      final filesRaw = offer['files'];
      if (filesRaw is! List) throw StateError('بيانات الملفات غير صالحة');
      final files = <TransferFile>[];
      for (final raw in filesRaw) {
        final m = Map<String, dynamic>.from(raw as Map);
        files.add(TransferFile(name: m['name'] as String, path: '', size: (m['size'] as num).toInt(), hash: m['hash'] as String?));
      }
      final total = files.fold<int>(0, (a, b) => a + b.size);
      final accepted = await _confirmReceive(offer['sender'] as String? ?? 'جهاز', files.length, total, offer['code'] as String? ?? '------');
      if (!accepted) { socket.write('{"type":"reject"}\n'); await socket.flush(); return; }
      final service = TransferService(storage!);
      await service.receive(socket: socket, files: files, reader: reader, sessionId: offer['session'] as String?, onProgress: (_) {});
      await storage!.addHistory(TransferRecord(id: DateTime.now().microsecondsSinceEpoch.toString(), direction: TransferDirection.received, device: offer['sender'] as String? ?? 'جهاز', totalBytes: total, completedBytes: total, status: 'نجح', createdAt: DateTime.now()));
      if (context != null && context!.mounted) ScaffoldMessenger.of(context!).showSnackBar(SnackBar(content: Text('اكتمل استقبال ${files.length} عنصر')));
    } catch (e) {
      if (context != null && context!.mounted) ScaffoldMessenger.of(context!).showSnackBar(SnackBar(content: Text('فشل الاستقبال: ${e.toString().replaceFirst('Bad state: ', '')}')));
    } finally { socket.destroy(); }
  }
  Future<bool> _confirmReceive(String sender, int count, int total, String code) async {
    final c = context; if (c == null || !c.mounted) return false;
    return await showDialog<bool>(context: c, builder: (ctx) => AlertDialog(
      title: const Text('طلب استقبال'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$sender يريد إرسال $count عنصر.'), const SizedBox(height: 8), Text('الحجم: ${bytesText(total)}'), const SizedBox(height: 14), Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Text('رمز التحقق\n$code', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رفض')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استقبال'))],
    )) ?? false;
  }
  void stop() { running = false; server = null; }
}

class SendFlow extends StatefulWidget {
  const SendFlow({super.key, required this.storage, required this.discovery, required this.files, required this.initialDevices, this.selected});
  final StorageService storage; final DiscoveryService discovery; final List<TransferFile> files; final List<NearbyDevice> initialDevices; final NearbyDevice? selected;
  @override State<SendFlow> createState() => _SendFlowState();
}
class _SendFlowState extends State<SendFlow> {
  NearbyDevice? selected; List<NearbyDevice> devices = const []; StreamSubscription<List<NearbyDevice>>? sub; TransferProgress? progress; bool sending = false; String error = '';
  @override void initState() { super.initState(); selected = widget.selected; devices = widget.initialDevices; sub = widget.discovery.devices.listen((v) { if (mounted) setState(() => devices = v); }); }
  @override void dispose() { sub?.cancel(); super.dispose(); }
  Future<void> send() async {
    if (selected == null || sending) return;
    setState(() { sending = true; error = ''; });
    final socket = await widget.discovery.connect(selected!);
    if (socket == null) { if (mounted) setState(() { sending = false; error = 'تعذر الاتصال. تأكد أن الجهاز الآخر فتح وصلة وفعّل الاستقبال.'; }); return; }
    try {
      final service = TransferService(widget.storage); final sender = await widget.storage.deviceName();
      await service.send(socket: socket, senderName: sender, files: widget.files, onProgress: (p) { if (mounted) setState(() => progress = p); });
      final total = widget.files.fold<int>(0, (a, b) => a + b.size);
      await widget.storage.addHistory(TransferRecord(id: DateTime.now().microsecondsSinceEpoch.toString(), direction: TransferDirection.sent, device: selected!.name, totalBytes: total, completedBytes: total, status: 'نجح', createdAt: DateTime.now()));
      if (mounted) setState(() { sending = false; error = 'تم الإرسال والتحقق بنجاح ✓'; });
    } catch (e) { if (mounted) setState(() { sending = false; error = 'لم يكتمل الإرسال: ${e.toString().replaceFirst('Bad state: ', '')}'; }); }
    finally { socket.destroy(); }
  }
  @override Widget build(BuildContext context) {
    final total = widget.files.fold<int>(0, (a, b) => a + b.size); final p = progress; final frac = p == null || p.total == 0 ? 0.0 : (p.bytes / p.total).clamp(0.0, 1.0).toDouble();
    return Scaffold(appBar: AppBar(title: const Text('إرسال الملفات')), body: ListView(padding: const EdgeInsets.all(18), children: [
      StepHeader(number: 1, title: 'ما الذي سترسله؟', subtitle: '${widget.files.length} عنصر • ${bytesText(total)}'),
      Card(child: Column(children: widget.files.take(8).map((f) => ListTile(leading: const Icon(Icons.insert_drive_file_rounded), title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(bytesText(f.size))).toList())),
      if (widget.files.length > 8) Padding(padding: const EdgeInsets.all(12), child: Text('+ ${widget.files.length - 8} عناصر أخرى')),
      const SizedBox(height: 18),
      StepHeader(number: 2, title: 'إلى أي جهاز؟', subtitle: selected == null ? 'اختر جهازاً من القائمة' : 'تم اختيار ${selected!.name}'),
      if (devices.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [const Icon(Icons.wifi_find_rounded, size: 40), const SizedBox(height: 8), const Text('لا توجد أجهزة متاحة'), const SizedBox(height: 4), const Text('افتح وصلة على الجهاز المستلم وفعّل الاستقبال.', textAlign: TextAlign.center)]))) else ...devices.map((d) => Card(color: selected?.id == d.id ? Theme.of(context).colorScheme.primaryContainer : null, child: ListTile(onTap: sending ? null : () => setState(() => selected = d), leading: Icon(selected?.id == d.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded), title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(d.host), trailing: selected?.id == d.id ? const Icon(Icons.check_circle_rounded) : null))),
      const SizedBox(height: 18),
      if (p != null) ...[LinearProgressIndicator(value: frac, minHeight: 9, borderRadius: BorderRadius.circular(8)), const SizedBox(height: 9), Text('${(frac * 100).toStringAsFixed(0)}% • ${speedText(p.speed)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8)],
      if (error.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(error, textAlign: TextAlign.center, style: TextStyle(color: error.contains('بنجاح') ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: selected == null || sending ? null : send, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'جاري الإرسال...' : 'إرسال الآن')),
      const SizedBox(height: 8),
      if (selected == null) const Text('لن يبدأ الإرسال حتى تختار جهازاً.', textAlign: TextAlign.center),
    ]));
  }
}

class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.number, required this.title, required this.subtitle});
  final int number; final String title, subtitle;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(children: [CircleAvatar(radius: 15, child: Text('$number')), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]))]));
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<ScanPage> createState() => _ScanPageState();
}
class _ScanPageState extends State<ScanPage> {
  bool handled = false; String message = 'وجّه الكاميرا نحو QR الخاص بوصلة';
  void onDetect(BarcodeCapture capture) {
    if (handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || !raw.startsWith('WASLA:')) continue;
      try {
        final m = jsonDecode(raw.substring(6)) as Map<String, dynamic>;
        final host = m['host'] as String?; final port = (m['port'] as num?)?.toInt();
        if (host == null || port == null || port < 1 || port > 65535) throw const FormatException();
        handled = true;
        final d = NearbyDevice(id: 'qr-$host-$port', name: m['name'] as String? ?? 'جهاز قريب', host: host, port: port);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QrSendPage(storage: widget.storage, discovery: widget.discovery, target: d)));
        return;
      } catch (_) { setState(() => message = 'رمز QR غير صالح'); }
    }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('مسح QR')), body: Stack(children: [
    MobileScanner(onDetect: onDetect, errorBuilder: (context, error, child) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.no_photography_rounded, size: 58), const SizedBox(height: 12), const Text('تعذر تشغيل الكاميرا', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text('$error', textAlign: TextAlign.center), const SizedBox(height: 14), const Text('اسمح لتطبيق وصلة باستخدام الكاميرا من إعدادات أندرويد.', textAlign: TextAlign.center)])))),
    Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Container(margin: const EdgeInsets.all(18), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(16)), child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), textAlign: TextAlign.center))))
  ]));
}

class QrSendPage extends StatelessWidget {
  const QrSendPage({super.key, required this.storage, required this.discovery, required this.target});
  final StorageService storage; final DiscoveryService discovery; final NearbyDevice target;
  Future<void> choose(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true); if (r == null || !context.mounted) return;
    final files = <TransferFile>[]; for (final i in r.files) { if (i.path != null) { final f = File(i.path!); if (f.existsSync()) files.add(TransferFile(name: i.name, path: i.path!, size: f.lengthSync())); } }
    if (!context.mounted || files.isEmpty) return; Navigator.push(context, MaterialPageRoute(builder: (_) => SendFlow(storage: storage, discovery: discovery, files: files, initialDevices: [target], selected: target)));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('جهاز QR')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle_rounded, size: 64), const SizedBox(height: 12), Text(target.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), Text('${target.host}:${target.port}'), const SizedBox(height: 22), FilledButton.icon(onPressed: () => choose(context), icon: const Icon(Icons.folder_open_rounded), label: const Text('اختيار الملفات وإرسال'))])));
}

class QrPage extends StatefulWidget {
  const QrPage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<QrPage> createState() => _QrPageState();
}
class _QrPageState extends State<QrPage> {
  String payload = '';
  @override void initState() { super.initState(); _make(); }
  Future<void> _make() async {
    final name = await widget.storage.deviceName(); final server = await widget.discovery.transferServer;
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
    var ip = ''; for (final i in interfaces) { for (final a in i.addresses) { if (!a.address.startsWith('127.')) { ip = a.address; break; } } if (ip.isNotEmpty) break; }
    if (mounted) setState(() => payload = jsonEncode({'v': 1, 'host': ip, 'port': server.port, 'name': name}));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('QR للاتصال')), body: Center(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [const Text('على الجهاز الآخر: مسح QR ثم اختيار الملفات.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 18), if (payload.isNotEmpty) Center(child: QrImageView(data: 'WASLA:$payload', size: 270, backgroundColor: Colors.white, padding: const EdgeInsets.all(16))), const SizedBox(height: 12), SelectableText(payload.isEmpty ? 'جاري تجهيز الرمز...' : payload, textAlign: TextAlign.center)])));
}

class ManualPage extends StatefulWidget {
  const ManualPage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<ManualPage> createState() => _ManualPageState();
}
class _ManualPageState extends State<ManualPage> {
  final host = TextEditingController(); final port = TextEditingController(text: '');
  @override void dispose() { host.dispose(); port.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('اتصال يدوي')), body: ListView(padding: const EdgeInsets.all(20), children: [const Text('استخدم هذا فقط إذا لم يظهر الجهاز تلقائياً.', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 18), TextField(controller: host, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'عنوان IP', hintText: '192.168.1.20', prefixIcon: Icon(Icons.language_rounded))), const SizedBox(height: 12), TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المنفذ', hintText: 'مثال 45455', prefixIcon: Icon(Icons.settings_ethernet_rounded))), const SizedBox(height: 18), FilledButton.icon(onPressed: () async { final p = int.tryParse(port.text.trim()); if (host.text.trim().isEmpty || p == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل IP والمنفذ بشكل صحيح.'))); return; } final d = NearbyDevice(id: 'manual', name: 'الجهاز الآخر', host: host.text.trim(), port: p); final r = await FilePicker.platform.pickFiles(allowMultiple: true); if (r == null || !context.mounted) return; final files = <TransferFile>[]; for (final i in r.files) { if (i.path != null) { final f = File(i.path!); if (f.existsSync()) files.add(TransferFile(name: i.name, path: i.path!, size: f.lengthSync())); } } if (!context.mounted || files.isEmpty) return; Navigator.push(context, MaterialPageRoute(builder: (_) => SendFlow(storage: widget.storage, discovery: widget.discovery, files: files, initialDevices: [d], selected: d))); }, icon: const Icon(Icons.send_rounded), label: const Text('اختيار الملفات والمتابعة'))]));
}

class AppPage extends StatefulWidget {
  const AppPage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<AppPage> createState() => _AppPageState();
}
class _AppPageState extends State<AppPage> {
  List<AppItem> apps = const []; final selected = <String>{}; bool loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final v = await installedApps(); if (mounted) setState(() => apps = v); } finally { if (mounted) setState(() => loading = false); } }
  Future<void> sendApps() async { final chosen = apps.where((a) => selected.contains(a.packageName)).toList(); final files = <TransferFile>[]; for (final a in chosen) { final p = await exportApp(a.packageName); if (p != null) files.add(TransferFile(name: '${a.name}.apk', path: p, size: File(p).lengthSync())); } if (!mounted || files.isEmpty) return; Navigator.push(context, MaterialPageRoute(builder: (_) => SendFlow(storage: widget.storage, discovery: widget.discovery, files: files, initialDevices: const []))); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('التطبيقات المثبتة')), body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(14), children: [Text('${apps.length} تطبيق', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), ...apps.map((a) => Card(child: CheckboxListTile(value: selected.contains(a.packageName), onChanged: (v) => setState(() => v == true ? selected.add(a.packageName) : selected.remove(a.packageName),), title: Text(a.name), subtitle: Text(bytesText(a.size)), secondary: const Icon(Icons.android_rounded)))), FilledButton.icon(onPressed: selected.isEmpty ? null : sendApps, icon: const Icon(Icons.send_rounded), label: Text('إرسال ${selected.length} تطبيق'))]));
}

class HistoryPage extends StatefulWidget { const HistoryPage({super.key, required this.storage}); final StorageService storage; @override State<HistoryPage> createState() => _HistoryPageState(); }
class _HistoryPageState extends State<HistoryPage> {
  List<TransferRecord> records = const [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await widget.storage.history(); if (mounted) setState(() => records = r); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('سجل النقل'), actions: [IconButton(onPressed: () async { await widget.storage.clearHistory(); _load(); }, icon: const Icon(Icons.delete_outline_rounded))]), body: records.isEmpty ? const Center(child: Text('لا توجد عمليات نقل بعد.')) : ListView.builder(padding: const EdgeInsets.all(14), itemCount: records.length, itemBuilder: (_, i) { final r = records[i]; return Card(child: ListTile(leading: Icon(r.direction == TransferDirection.sent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded), title: Text(r.device, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${bytesText(r.completedBytes)} • ${r.status}\n${r.createdAt.toLocal()}'), isThreeLine: true)); }));
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key, required this.storage}); final StorageService storage; @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final c = TextEditingController();
  @override void initState() { super.initState(); widget.storage.deviceName().then((v) { if (mounted) c.text = v; }); }
  @override void dispose() { c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: ListView(padding: const EdgeInsets.all(20), children: [TextField(controller: c, decoration: const InputDecoration(labelText: 'اسم الجهاز', prefixIcon: Icon(Icons.phone_android_rounded))), const SizedBox(height: 14), FilledButton(onPressed: () async { await widget.storage.setDeviceName(c.text.trim().isEmpty ? 'هاتف وصلة' : c.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اسم الجهاز'))); }, child: const Text('حفظ')), const SizedBox(height: 20), const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('وصلة تعمل داخل الشبكة المحلية. لا يوجد حساب ولا خادم وسيط لنقل ملفاتك.')))]));
}
