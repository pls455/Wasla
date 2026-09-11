import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

const _appsChannel = MethodChannel('com.wasla/apps');

Future<List<AppItem>> loadInstalledApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await _appsChannel.invokeMethod<List<dynamic>>('listApps') ?? const [];
  return raw.map((e) => AppItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
}

Future<String?> exportInstalledApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return _appsChannel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

class AppItem {
  const AppItem({required this.packageName, required this.name, required this.size, this.iconBase64});
  final String packageName;
  final String name;
  final int size;
  final String? iconBase64;
  factory AppItem.fromMap(Map<String, dynamic> map) => AppItem(packageName: map['packageName'] as String? ?? '', name: map['name'] as String? ?? 'تطبيق', size: (map['size'] as num?)?.toInt() ?? 0, iconBase64: map['icon'] as String?);
}

void main() => runApp(const WaslaApp());

class WaslaApp extends StatefulWidget {
  const WaslaApp({super.key});
  @override State<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends State<WaslaApp> {
  final storage = StorageService();
  late final DiscoveryService discovery = DiscoveryService(storage);
  ThemeMode themeMode = ThemeMode.dark;
  @override void initState() { super.initState(); discovery.start(); }
  @override void dispose() { discovery.dispose(); super.dispose(); }
  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF), brightness: brightness);
    return ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, scaffoldBackgroundColor: dark ? const Color(0xFF08090D) : const Color(0xFFF7F7FA), appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0), inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none), filled: true));
  }
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner: false, title: 'وصلة | Wasla', theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), themeMode: themeMode, home: HomePage(storage: storage, discovery: discovery, onToggleTheme: () => setState(() => themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark)));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.storage, required this.discovery, required this.onToggleTheme});
  final StorageService storage;
  final DiscoveryService discovery;
  final VoidCallback onToggleTheme;
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NearbyDevice> devices = const [];
  String deviceName = 'هاتف وصلة';
  late final StreamSubscription<List<NearbyDevice>> _devicesSub;
  @override void initState() {
    super.initState();
    widget.storage.deviceName().then((name) { if (mounted) setState(() => deviceName = name); });
    _devicesSub = widget.discovery.devices.listen((value) { if (mounted) setState(() => devices = value); });
  }
  @override void dispose() { _devicesSub.cancel(); super.dispose(); }
  Future<void> _pickFiles({NearbyDevice? target}) async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    if (!mounted || picked.isEmpty) return;
    final files = picked.where((f) => f.path != null).map((f) { final path = f.path!; return TransferFile(name: f.name, path: path, size: File(path).lengthSync()); }).toList();
    if (files.isEmpty || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files, target: target)));
  }
  void _openApps({NearbyDevice? target}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AppPickerPage(onReady: (files) { Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files, target: target))); })));
  }
  void _sendOptions({NearbyDevice? target}) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheet) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('ماذا تريد أن ترسل؟', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(target == null ? 'اختر المحتوى ثم الجهاز.' : 'إلى ${target.name}'), const SizedBox(height: 16), _ActionTile(icon: Icons.folder_rounded, title: 'ملفات', subtitle: 'صور، فيديو، مستندات وغيرها', onTap: () { Navigator.pop(sheet); _pickFiles(target: target); }), _ActionTile(icon: Icons.apps_rounded, title: 'تطبيقات', subtitle: 'اختر تطبيقات مثبتة على الهاتف', onTap: () { Navigator.pop(sheet); _openApps(target: target); })]))));
  }
  @override Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('وصلة', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), Text('WASLA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2))]), actions: [IconButton(onPressed: widget.onToggleTheme, tooltip: 'المظهر', icon: const Icon(Icons.contrast_rounded)), IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(storage: widget.storage))), tooltip: 'الإعدادات', icon: const Icon(Icons.settings_outlined))]), body: RefreshIndicator(onRefresh: widget.discovery.start, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 36), children: [const Text('أرسل ملفاتك مباشرة.', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900, height: 1.1)), const SizedBox(height: 8), const Text('نقل محلي مباشر، بدون خادم وسيط.', style: TextStyle(fontSize: 14)), const SizedBox(height: 24), Row(children: [Expanded(child: _BigAction(icon: Icons.arrow_upward_rounded, title: 'إرسال', subtitle: 'ملفات أو تطبيقات', primary: true, onTap: _sendOptions)), const SizedBox(width: 12), Expanded(child: _BigAction(icon: Icons.arrow_downward_rounded, title: 'استقبال', subtitle: 'انتظر طلبًا', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceivePage(storage: widget.storage, discovery: widget.discovery))))]), const SizedBox(height: 28), Row(children: [const Icon(Icons.radar_rounded, size: 21), const SizedBox(width: 8), const Text('الأجهزة القريبة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const Spacer(), Text('${devices.length}')]), const SizedBox(height: 10), if (devices.isEmpty) const _EmptyNearby() else ...devices.map((device) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _DeviceTile(device: device, onTap: () => _sendOptions(target: device)))), const SizedBox(height: 14), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(22)), child: Row(children: [const Icon(Icons.lock_outline_rounded), const SizedBox(width: 12), Expanded(child: Text('هذا الجهاز: $deviceName\nالنقل محلي ومباشر.', style: const TextStyle(fontWeight: FontWeight.w700)))]))]))));
  }
}

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.storage, required this.discovery, required this.files, this.target});
  final StorageService storage; final DiscoveryService discovery; final List<TransferFile> files; final NearbyDevice? target;
  @override State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late final TransferService transfer = TransferService(widget.storage);
  NearbyDevice? selected; TransferProgress? progress; String status = 'اختر جهازًا للبدء'; bool running = false; List<NearbyDevice> devices = const [];
  late final StreamSubscription<List<NearbyDevice>> _sub;
  @override void initState() { super.initState(); selected = widget.target; _sub = widget.discovery.devices.listen((value) { if (mounted) setState(() => devices = value); }); }
  @override void dispose() { _sub.cancel(); super.dispose(); }
  Future<void> _start() async {
    final device = selected; if (device == null || running) return;
    setState(() { running = true; status = 'جاري الاتصال...'; });
    final socket = await widget.discovery.connect(device);
    if (socket == null) { if (mounted) setState(() { running = false; status = 'تعذر الاتصال بالجهاز'; }); return; }
    try {
      final name = await widget.storage.deviceName();
      await transfer.send(socket: socket, senderName: name, files: widget.files, onProgress: (p) { if (mounted) setState(() { progress = p; status = p.status; }); });
      final total = widget.files.fold<int>(0, (a, b) => a + b.size);
      await widget.storage.addHistory(TransferRecord(id: '${DateTime.now().microsecondsSinceEpoch}', direction: TransferDirection.sent, device: device.name, totalBytes: total, completedBytes: total, status: 'completed', createdAt: DateTime.now()));
    } catch (e) { if (mounted) setState(() => status = _error(e)); }
    finally { socket.destroy(); if (mounted) setState(() => running = false); }
  }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('إرسال', style: TextStyle(fontWeight: FontWeight.w900))), body: ListView(padding: const EdgeInsets.all(20), children: [_TransferSummary(files: widget.files), const SizedBox(height: 18), if (selected == null) ...[const Text('اختر الجهاز', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 10), if (devices.isEmpty) const _EmptyNearby() else ...devices.map((d) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _DeviceTile(device: d, selected: selected?.id == d.id, onTap: () => setState(() => selected = d))))] else _DeviceTile(device: selected!, selected: true, onTap: running ? null : () => setState(() => selected = null)), const SizedBox(height: 18), if (progress != null) _ProgressCard(progress: progress!), const SizedBox(height: 12), Text(status, textAlign: TextAlign.center), const SizedBox(height: 18), FilledButton.icon(onPressed: selected == null || running ? null : _start, icon: Icon(running ? Icons.sync_rounded : Icons.send_rounded), label: Text(running ? 'جاري الإرسال...' : 'ابدأ الإرسال'))]));
}

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, required this.storage, required this.discovery});
  final StorageService storage; final DiscoveryService discovery;
  @override State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  ServerSocket? server; StreamSubscription<Socket>? _sub; TransferProgress? progress; String status = 'في انتظار جهاز مرسل...'; bool busy = false;
  @override void initState() { super.initState(); _listen(); }
  Future<void> _listen() async { server = await widget.discovery.transferServer; if (server == null || !mounted) return; _sub = server!.listen(_handleSocket); }
  Future<void> _handleSocket(Socket socket) async {
    if (busy) { socket.destroy(); return; } busy = true; final reader = SocketReader(socket);
    try {
      final offer = await reader.readLine(); if (offer['type'] != 'offer') throw StateError('طلب نقل غير صالح');
      final raw = offer['files'] as List<dynamic>? ?? const [];
      final files = raw.map((e) { final m = Map<String, dynamic>.from(e as Map); return TransferFile(name: m['name'] as String, path: '', size: (m['size'] as num).toInt(), hash: m['hash'] as String?); }).toList();
      if (mounted) setState(() => status = 'استقبال ${files.length} ملف من ${offer['sender'] ?? 'جهاز'}');
      await TransferService(widget.storage).receive(socket: socket, files: files, reader: reader, onProgress: (p) { if (mounted) setState(() { progress = p; status = p.status; }); });
      final total = files.fold<int>(0, (a, b) => a + b.size);
      await widget.storage.addHistory(TransferRecord(id: '${DateTime.now().microsecondsSinceEpoch}', direction: TransferDirection.received, device: offer['sender']?.toString() ?? 'جهاز قريب', totalBytes: total, completedBytes: total, status: 'completed', createdAt: DateTime.now()));
    } catch (e) { if (mounted) setState(() => status = _error(e)); }
    finally { socket.destroy(); busy = false; }
  }
  @override void dispose() { _sub?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final icon = progress == null ? Icons.wifi_tethering_rounded : Icons.download_done_rounded;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('استقبال', style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 70), const SizedBox(height: 20), Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), if (progress != null) ...[const SizedBox(height: 20), _ProgressCard(progress: progress!)] else ...[const SizedBox(height: 12), const Text('افتح وصلة على الجهاز الآخر واختر هذا الجهاز.', textAlign: TextAlign.center)]]))));
  }
}

class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.onReady});
  final void Function(List<TransferFile>) onReady;
  @override State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppItem> apps = const []; final selected = <String>{}; bool loading = true; String query = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final value = await loadInstalledApps(); value.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())); if (mounted) setState(() { apps = value; loading = false; }); } catch (_) { if (mounted) setState(() => loading = false); } }
  Future<void> _prepare() async {
    final files = <TransferFile>[];
    for (final app in apps.where((a) => selected.contains(a.packageName))) { final path = await exportInstalledApp(app.packageName); if (path != null) { final file = File(path); if (file.existsSync()) files.add(TransferFile(name: '${app.name}.apk', path: path, size: file.lengthSync())); } }
    if (!mounted) return;
    if (files.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تجهيز التطبيقات المحددة.'))); return; }
    widget.onReady(files); Navigator.pop(context);
  }
  @override Widget build(BuildContext context) {
    final shown = apps.where((a) => a.name.toLowerCase().contains(query.toLowerCase()) || a.packageName.toLowerCase().contains(query.toLowerCase())).toList();
    final list = <Widget>[TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(hintText: 'ابحث عن تطبيق', prefixIcon: Icon(Icons.search_rounded))), const SizedBox(height: 14), Text('${shown.length} تطبيق متاح'), const SizedBox(height: 8)];
    for (final app in shown) { list.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _AppTile(app: app, selected: selected.contains(app.packageName), onTap: () => setState(() { if (selected.contains(app.packageName)) { selected.remove(app.packageName); } else { selected.add(app.packageName); } })))); }
    if (shown.isEmpty) list.add(const Padding(padding: EdgeInsets.only(top: 70), child: Center(child: Text('لم نجد تطبيقًا بهذا الاسم'))));
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('التطبيقات', style: TextStyle(fontWeight: FontWeight.w900)), actions: selected.isEmpty ? const [] : [Padding(padding: const EdgeInsets.all(14), child: Center(child: Text('${selected.length} محدد')))]), bottomNavigationBar: selected.isEmpty ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 14), child: FilledButton.icon(onPressed: _prepare, icon: const Icon(Icons.send_rounded), label: Text('تجهيز ${selected.length} تطبيق')))), body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: list)));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.storage});
  final StorageService storage;
  @override State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  final controller = TextEditingController(); bool saving = false;
  @override void initState() { super.initState(); widget.storage.deviceName().then((v) { if (mounted) controller.text = v; }); }
  @override void dispose() { controller.dispose(); super.dispose(); }
  Future<void> _save() async { setState(() => saving = true); await widget.storage.setDeviceName(controller.text); if (!mounted) return; setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اسم الجهاز.'))); }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.w900))), body: ListView(padding: const EdgeInsets.all(20), children: [const Text('اسم الجهاز', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8), TextField(controller: controller, textInputAction: TextInputAction.done), const SizedBox(height: 12), FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ')), const SizedBox(height: 24), const ListTile(leading: Icon(Icons.security_rounded), title: Text('خصوصية محلية'), subtitle: Text('الملفات تنتقل مباشرة بين الأجهزة ولا تحتاج خادمًا وسيطًا.'))])));
}

class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.title, required this.subtitle, required this.onTap, this.primary = false});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap; final bool primary;
  @override Widget build(BuildContext context) {
    return Card(
      color: primary ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 30),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override Widget build(BuildContext context) => ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 4), leading: CircleAvatar(radius: 25, child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left_rounded), onTap: onTap);
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap, this.selected = false});
  final NearbyDevice device; final VoidCallback? onTap; final bool selected;
  @override Widget build(BuildContext context) => Card(child: ListTile(onTap: onTap, leading: CircleAvatar(child: Icon(selected ? Icons.check_rounded : Icons.phone_android_rounded)), title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${device.host}:${device.port}'), trailing: Icon(selected ? Icons.check_circle_rounded : Icons.chevron_left_rounded)));
}

class _EmptyNearby extends StatelessWidget {
  const _EmptyNearby();
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Theme.of(context).dividerColor)), child: const Column(children: [Icon(Icons.devices_other_rounded, size: 38), SizedBox(height: 10), Text('لا توجد أجهزة قريبة حاليًا', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('تأكد أن الجهازين على الشبكة نفسها وافتح وصلة عليهما.', textAlign: TextAlign.center)]));
}

class _TransferSummary extends StatelessWidget {
  const _TransferSummary({required this.files}); final List<TransferFile> files;
  @override Widget build(BuildContext context) { final total = files.fold<int>(0, (a, b) => a + b.size); return Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [const Icon(Icons.folder_copy_rounded, size: 30), const SizedBox(width: 12), Expanded(child: Text('${files.length} ملف\n${_fmt(total)}', style: const TextStyle(fontWeight: FontWeight.w800)))]))); }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress}); final TransferProgress progress;
  @override Widget build(BuildContext context) { final value = progress.total == 0 ? 0.0 : (progress.bytes / progress.total).clamp(0.0, 1.0).toDouble(); return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [LinearProgressIndicator(value: value, minHeight: 8, borderRadius: BorderRadius.circular(8)), const SizedBox(height: 10), Row(children: [Text('${(value * 100).round()}%'), const Spacer(), Text('${_fmt(progress.speed)}/ث')]), if (progress.eta != null) Text('متبقي تقريبًا ${_duration(progress.eta!)}')]))); }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.selected, required this.onTap}); final AppItem app; final bool selected; final VoidCallback onTap;
  @override Widget build(BuildContext context) => Card(child: ListTile(onTap: onTap, leading: const CircleAvatar(child: Icon(Icons.apps_rounded)), title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${app.packageName}\n${_fmt(app.size)}'), isThreeLine: true, trailing: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded)));
}

String _fmt(num bytes) { if (bytes < 1024) return '${bytes.round()} B'; if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB'; if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'; return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'; }
String _duration(Duration d) { final seconds = d.inSeconds; if (seconds < 60) return '${seconds}ث'; if (seconds < 3600) return '${seconds ~/ 60}د'; return '${seconds ~/ 3600}س'; }
String _error(Object e) => e is StateError ? e.toString() : 'حدث خطأ أثناء النقل.';
