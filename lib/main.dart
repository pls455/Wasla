import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

void main() => runApp(const WaslaApp());

class WaslaApp extends StatefulWidget {
  const WaslaApp({super.key});
  @override State<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends State<WaslaApp> {
  final storage = StorageService();
  late final discovery = DiscoveryService(storage);
  bool dark = true;
  @override void initState() { super.initState(); discovery.start(); }
  @override void dispose() { discovery.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'وصلة | Wasla',
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark),
    home: HomePage(storage: storage, discovery: discovery, toggleTheme: () => setState(() => dark = !dark)),
  );
  ThemeData _theme(Brightness b) => ThemeData(useMaterial3: true, brightness: b, colorSchemeSeed: const Color(0xFF5B7CFF), scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF090B10) : const Color(0xFFF7F8FC));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.storage, required this.discovery, required this.toggleTheme});
  final StorageService storage; final DiscoveryService discovery; final VoidCallback toggleTheme;
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NearbyDevice> devices = [];
  String name = 'هاتف وصلة';
  @override void initState() {
    super.initState();
    widget.storage.deviceName().then((v) { if (mounted) setState(() => name = v); });
    widget.discovery.devices.listen((d) { if (mounted) setState(() => devices = d); });
  }

  Future<void> _pick({NearbyDevice? target}) async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    if (!mounted || picked.isEmpty) return;
    final files = picked.where((f) => f.path != null).map((f) => TransferFile(name: f.name, path: f.path!, size: f.size)).toList();
    if (files.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files, deviceName: name, target: target)));
  }

  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('وصلة', style: TextStyle(fontWeight: FontWeight.w900)), actions: [
      IconButton(onPressed: widget.toggleTheme, icon: const Icon(Icons.brightness_6_rounded)),
      IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(storage: widget.storage))), icon: const Icon(Icons.settings_rounded)),
    ]),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      const Text('نقل مباشر. بدون وسيط.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(height: 7),
      Text('ملفاتك تنتقل من جهاز إلى جهاز عبر الشبكة المحلية.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: _Action(icon: Icons.upload_rounded, title: 'إرسال', subtitle: 'اختر ملفاتك', onTap: () => _pick())),
        const SizedBox(width: 12),
        Expanded(child: _Action(icon: Icons.download_rounded, title: 'استقبال', subtitle: 'انتظر اتصالاً', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceivePage(storage: widget.storage, discovery: widget.discovery))))),
      ]),
      const SizedBox(height: 30),
      Row(children: [const Icon(Icons.radar_rounded), const SizedBox(width: 8), const Text('أجهزة قريبة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(), Text('${devices.length}')]),
      const SizedBox(height: 10),
      if (devices.isEmpty) const _EmptyNearby() else ...devices.map((d) => _DeviceTile(device: d, onTap: () => _pick(target: d))),
      const SizedBox(height: 20),
      const _PrivacyStrip(),
    ]),
  ));
}

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.storage, required this.discovery, required this.files, required this.deviceName, this.target});
  final StorageService storage; final DiscoveryService discovery; final List<TransferFile> files; final String deviceName; final NearbyDevice? target;
  @override State<SendPage> createState() => _SendPageState();
}
class _SendPageState extends State<SendPage> {
  NearbyDevice? selected; TransferProgress? progress; String status = 'اختر جهازاً قريباً'; bool running = false;
  @override void initState() { super.initState(); selected = widget.target; if (selected != null) _start(); }
  Future<void> _start() async {
    if (running || selected == null) return;
    setState(() => running = true);
    final socket = await widget.discovery.connect(selected!);
    if (socket == null) { if (mounted) setState(() { running = false; status = 'تعذر الاتصال بالجهاز'; }); return; }
    try {
      await TransferService(widget.storage).send(socket: socket, senderName: widget.deviceName, files: widget.files, onProgress: (p) { if (mounted) setState(() => progress = p); });
      await widget.storage.addHistory(TransferRecord(id: DateTime.now().toIso8601String(), direction: TransferDirection.sent, device: selected!.name, totalBytes: widget.files.fold(0, (a, b) => a + b.size), completedBytes: widget.files.fold(0, (a, b) => a + b.size), status: 'success', createdAt: DateTime.now()));
      if (mounted) setState(() => status = 'اكتمل النقل والتحقق');
    } catch (e) { if (mounted) setState(() => status = e.toString().replaceFirst('Bad state: ', '')); }
    finally { await socket.close(); if (mounted) setState(() => running = false); }
  }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('إرسال')), body: ListView(padding: const EdgeInsets.all(20), children: [
    _TransferCard(progress: progress, files: widget.files, status: status), const SizedBox(height: 20),
    if (selected == null) StreamBuilder<List<NearbyDevice>>(stream: widget.discovery.devices, initialData: const [], builder: (c, s) => Column(children: s.data!.map((d) => _DeviceTile(device: d, onTap: () { setState(() => selected = d); _start(); })).toList())),
    if (selected != null && !running && progress == null) FilledButton.icon(onPressed: _start, icon: const Icon(Icons.bolt_rounded), label: const Text('بدء النقل')),
  ])));
}

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<ReceivePage> createState() => _ReceivePageState();
}
class _ReceivePageState extends State<ReceivePage> {
  ServerSocket? server; Socket? pending; SocketReader? reader; Map<String, dynamic>? offer; TransferProgress? progress; bool busy = false;
  @override void initState() { super.initState(); _listen(); }
  Future<void> _listen() async {
    server = await widget.discovery.transferServer;
    server?.listen((socket) async {
      if (busy || pending != null) { await socket.close(); return; }
      pending = socket; reader = SocketReader(socket);
      try { final first = await reader!.readLine(); if (first['type'] == 'offer' && mounted) setState(() => offer = first); } catch (_) { await socket.close(); }
    });
  }
  Future<void> _accept() async {
    final socket = pending; final input = reader; final o = offer; if (socket == null || input == null || o == null) return;
    setState(() => busy = true);
    final files = (o['files'] as List).map((e) => TransferFile(name: e['name'], path: '', size: (e['size'] as num).toInt(), hash: e['hash'])).toList();
    try {
      await TransferService(widget.storage).receive(socket: socket, reader: input, files: files, onProgress: (p) { if (mounted) setState(() => progress = p); });
      await widget.storage.addHistory(TransferRecord(id: DateTime.now().toIso8601String(), direction: TransferDirection.received, device: o['sender'] ?? 'جهاز', totalBytes: files.fold(0, (a, b) => a + b.size), completedBytes: files.fold(0, (a, b) => a + b.size), status: 'success', createdAt: DateTime.now()));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { await socket.close(); if (mounted) setState(() { busy = false; pending = null; reader = null; offer = null; }); }
  }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('استقبال')), body: ListView(padding: const EdgeInsets.all(20), children: [
    if (offer != null) _IncomingCard(offer: offer!, onAccept: _accept, onReject: () async { await pending?.close(); if (mounted) setState(() { pending = null; reader = null; offer = null; }); }),
    if (offer == null && progress == null) const _EmptyReceive(), if (progress != null) _TransferCard(progress: progress, files: const [], status: progress!.status),
  ])));
}

class SettingsPage extends StatefulWidget { const SettingsPage({super.key, required this.storage}); final StorageService storage; @override State<SettingsPage> createState() => _SettingsState(); }
class _SettingsState extends State<SettingsPage> { late final c = TextEditingController(); @override void initState() { super.initState(); widget.storage.deviceName().then((v) { if (mounted) c.text = v; }); } @override void dispose() { c.dispose(); super.dispose(); } @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: ListView(padding: const EdgeInsets.all(20), children: [TextField(controller: c, decoration: const InputDecoration(labelText: 'اسم الجهاز', border: OutlineInputBorder())), const SizedBox(height: 12), FilledButton(onPressed: () async { await widget.storage.setDeviceName(c.text); if (mounted) Navigator.pop(context); }, child: const Text('حفظ')), const SizedBox(height: 24), const ListTile(leading: Icon(Icons.shield_rounded), title: Text('الخصوصية'), subtitle: Text('النقل يتم محلياً بين الأجهزة ولا نستخدم خادماً لتخزين الملفات.'))]))); }

class _Action extends StatelessWidget { const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap}); final IconData icon; final String title, subtitle; final VoidCallback onTap; @override Widget build(BuildContext c) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Theme.of(c).colorScheme.surfaceContainerHighest), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 30), const SizedBox(height: 15), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), Text(subtitle, style: const TextStyle(color: Colors.grey))]))); }
class _DeviceTile extends StatelessWidget { const _DeviceTile({required this.device, required this.onTap}); final NearbyDevice device; final VoidCallback onTap; @override Widget build(BuildContext c) => ListTile(onTap: onTap, leading: const CircleAvatar(child: Icon(Icons.phone_android_rounded)), title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${device.host} • جاهز'), trailing: const Icon(Icons.chevron_left_rounded)); }
class _EmptyNearby extends StatelessWidget { const _EmptyNearby(); @override Widget build(BuildContext c) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Theme.of(c).dividerColor)), child: const Column(children: [Icon(Icons.wifi_find_rounded, size: 40), SizedBox(height: 8), Text('نبحث عن أجهزة قريبة…', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('افتح وصلة على الجهاز الآخر واتصل بنفس شبكة Wi‑Fi.', textAlign: TextAlign.center)])); }
class _PrivacyStrip extends StatelessWidget { const _PrivacyStrip(); @override Widget build(BuildContext c) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Theme.of(c).colorScheme.surfaceContainerHighest), child: const Row(children: [Icon(Icons.lock_outline_rounded), SizedBox(width: 10), Expanded(child: Text('ملفاتك تنتقل محلياً ولا تُرفع إلى خادم مركزي.', style: TextStyle(fontSize: 13)))])); }
class _EmptyReceive extends StatelessWidget { const _EmptyReceive(); @override Widget build(BuildContext c) => const Padding(padding: EdgeInsets.only(top: 80), child: Column(children: [Icon(Icons.download_for_offline_rounded, size: 64), SizedBox(height: 16), Text('بانتظار ملف', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('سيظهر طلب الاستقبال هنا قبل بدء أي نقل.', textAlign: TextAlign.center)])); }
class _IncomingCard extends StatelessWidget { const _IncomingCard({required this.offer, required this.onAccept, required this.onReject}); final Map<String, dynamic> offer; final VoidCallback onAccept, onReject; @override Widget build(BuildContext c) { final files = offer['files'] as List; return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: Theme.of(c).colorScheme.surfaceContainerHighest), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('طلب استقبال', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(offer['sender'] ?? 'جهاز قريب'), const SizedBox(height: 10), ...files.map((f) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.insert_drive_file_outlined), title: Text(f['name']), subtitle: Text(_fmt((f['size'] as num).toInt())))), Row(children: [Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('رفض'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: onAccept, child: const Text('استقبال')))])])); } }
class _TransferCard extends StatelessWidget { const _TransferCard({required this.progress, required this.files, required this.status}); final TransferProgress? progress; final List<TransferFile> files; final String status; @override Widget build(BuildContext c) { final p = progress; final ratio = p == null ? 0.0 : (p.total == 0 ? 0.0 : p.bytes / p.total); return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: Theme.of(c).colorScheme.surfaceContainerHighest), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.bolt_rounded, size: 36), const SizedBox(height: 14), Text(status, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), if (files.isNotEmpty) Text('${files.length} ملف • ${_fmt(files.fold(0, (a, b) => a + b.size))}'), const SizedBox(height: 16), LinearProgressIndicator(value: p == null ? null : ratio, minHeight: 8), if (p != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${_fmt(p.bytes)} / ${_fmt(p.total)} • ${_fmt(p.speed.round())}/ث${p.eta == null ? '' : ' • ${p.eta!.inSeconds} ث تقريباً'}'))])); } }
String _fmt(int n) { const units = ['B', 'KB', 'MB', 'GB']; double x = n.toDouble(); var i = 0; while (x >= 1024 && i < units.length - 1) { x /= 1024; i++; } return '${x.toStringAsFixed(x < 10 && i > 0 ? 1 : 0)} ${units[i]}'; }
