import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

const appsChannel = MethodChannel('com.wasla/apps');

class AppItem {
  const AppItem({required this.packageName, required this.name, required this.size});
  final String packageName;
  final String name;
  final int size;

  factory AppItem.fromMap(Map<String, dynamic> map) {
    return AppItem(
      packageName: map['packageName'] as String? ?? '',
      name: map['name'] as String? ?? 'تطبيق',
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }
}

Future<List<AppItem>> installedApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await appsChannel.invokeMethod<List<dynamic>>('listApps') ?? const [];
  return raw.map((item) => AppItem.fromMap(Map<String, dynamic>.from(item as Map))).toList();
}

Future<String?> exportApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return appsChannel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

void main() {
  runApp(const WaslaApp());
}

class WaslaApp extends StatefulWidget {
  const WaslaApp({super.key});

  @override
  State<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends State<WaslaApp> {
  final storage = StorageService();
  late final DiscoveryService discovery = DiscoveryService(storage);
  ThemeMode themeMode = ThemeMode.dark;

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
      seedColor: const Color(0xFF6C63FF),
      brightness: themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وصلة | Wasla',
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: scheme),
      home: HomePage(
        storage: storage,
        discovery: discovery,
        onTheme: () {
          setState(() {
            themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          });
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.storage, required this.discovery, required this.onTheme});
  final StorageService storage;
  final DiscoveryService discovery;
  final VoidCallback onTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NearbyDevice> devices = const [];
  late final StreamSubscription<List<NearbyDevice>> subscription;

  @override
  void initState() {
    super.initState();
    subscription = widget.discovery.devices.listen((value) {
      if (mounted) setState(() => devices = value);
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  Future<void> sendFiles({NearbyDevice? target}) async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    if (!mounted || picked.isEmpty) return;
    final files = <TransferFile>[];
    for (final item in picked) {
      final path = item.path;
      if (path == null) continue;
      files.add(TransferFile(name: item.name, path: path, size: File(path).lengthSync()));
    }
    if (files.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendPage(
          storage: widget.storage,
          discovery: widget.discovery,
          files: files,
          target: target,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('وصلة', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: widget.onTheme, icon: const Icon(Icons.contrast_rounded)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('نقل مباشر.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('ملفاتك تنتقل محليًا بين الأجهزة بدون خادم وسيط.'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: MainAction(icon: Icons.send_rounded, title: 'إرسال', onTap: () => sendFiles())),
                const SizedBox(width: 12),
                Expanded(child: MainAction(icon: Icons.download_rounded, title: 'استقبال', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceivePage(storage: widget.storage, discovery: widget.discovery))))),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text('الأجهزة القريبة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${devices.length}'),
              ],
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد أجهزة قريبة. تأكد أن الجهازين على الشبكة نفسها.', textAlign: TextAlign.center)))
            else
              for (final device in devices)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.phone_android_rounded)),
                    title: Text(device.name),
                    subtitle: Text(device.host),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => sendFiles(target: device),
                  ),
                ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AppPage(storage: widget.storage, discovery: widget.discovery)));
              },
              icon: const Icon(Icons.apps_rounded),
              label: const Text('إرسال تطبيقات مثبتة'),
            ),
          ],
        ),
      ),
    );
  }
}

class MainAction extends StatelessWidget {
  const MainAction({super.key, required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Icon(icon, size: 34),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.storage, required this.discovery, required this.files, this.target});
  final StorageService storage;
  final DiscoveryService discovery;
  final List<TransferFile> files;
  final NearbyDevice? target;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late final TransferService transfer = TransferService(widget.storage);
  NearbyDevice? selected;
  List<NearbyDevice> devices = const [];
  TransferProgress? progress;
  String status = 'اختر جهازًا';
  bool sending = false;
  late final StreamSubscription<List<NearbyDevice>> subscription;

  @override
  void initState() {
    super.initState();
    selected = widget.target;
    subscription = widget.discovery.devices.listen((value) {
      if (mounted) setState(() => devices = value);
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  Future<void> startSend() async {
    final device = selected;
    if (device == null || sending) return;
    setState(() { sending = true; status = 'جاري الاتصال...'; });
    final socket = await widget.discovery.connect(device);
    if (socket == null) {
      if (mounted) setState(() { sending = false; status = 'تعذر الاتصال'; });
      return;
    }
    try {
      final name = await widget.storage.deviceName();
      await transfer.send(
        socket: socket,
        senderName: name,
        files: widget.files,
        onProgress: (value) {
          if (mounted) setState(() { progress = value; status = value.status; });
        },
      );
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    } finally {
      socket.destroy();
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إرسال')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('${widget.files.length} ملف'))),
            const SizedBox(height: 16),
            if (selected == null)
              for (final device in devices)
                Card(
                  child: ListTile(
                    title: Text(device.name),
                    subtitle: Text(device.host),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => setState(() => selected = device),
                  ),
                )
            else
              Card(child: ListTile(title: Text(selected!.name), subtitle: Text(selected!.host), trailing: const Icon(Icons.check_circle_rounded))),
            const SizedBox(height: 16),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress!.total == 0 ? 0 : progress!.bytes / progress!.total),
              const SizedBox(height: 8),
              Text('${progress!.bytes} / ${progress!.total}'),
            ],
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: selected == null || sending ? null : startSend, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'جاري الإرسال...' : 'ابدأ الإرسال')),
          ],
        ),
      ),
    );
  }
}

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, required this.storage, required this.discovery});
  final StorageService storage;
  final DiscoveryService discovery;
  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  StreamSubscription<Socket>? subscription;
  TransferProgress? progress;
  String status = 'في انتظار جهاز مرسل...';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    startServer();
  }

  Future<void> startServer() async {
    final server = await widget.discovery.transferServer;
    if (!mounted || server == null) return;
    subscription = server.listen(handleSocket);
  }

  Future<void> handleSocket(Socket socket) async {
    if (busy) { socket.destroy(); return; }
    busy = true;
    final reader = SocketReader(socket);
    try {
      final offer = await reader.readLine();
      if (offer['type'] != 'offer') throw StateError('طلب نقل غير صالح');
      final list = offer['files'] as List<dynamic>? ?? const [];
      final files = <TransferFile>[];
      for (final item in list) {
        final map = Map<String, dynamic>.from(item as Map);
        files.add(TransferFile(name: map['name'] as String, path: '', size: (map['size'] as num).toInt(), hash: map['hash'] as String?));
      }
      if (mounted) setState(() => status = 'استقبال ${files.length} ملف');
      await TransferService(widget.storage).receive(
        socket: socket,
        files: files,
        reader: reader,
        onProgress: (value) {
          if (mounted) setState(() { progress = value; status = value.status; });
        },
      );
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    } finally {
      socket.destroy();
      busy = false;
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استقبال')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_tethering_rounded, size: 70),
                const SizedBox(height: 20),
                Text(status, textAlign: TextAlign.center),
                if (progress != null) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: progress!.total == 0 ? 0 : progress!.bytes / progress!.total),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppPage extends StatefulWidget {
  const AppPage({super.key, required this.storage, required this.discovery});
  final StorageService storage;
  final DiscoveryService discovery;
  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  List<AppItem> apps = const [];
  final selected = <String>{};
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final value = await installedApps();
      value.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() { apps = value; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> prepare() async {
    final files = <TransferFile>[];
    for (final app in apps) {
      if (!selected.contains(app.packageName)) continue;
      final path = await exportApp(app.packageName);
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) files.add(TransferFile(name: '${app.name}.apk', path: path, size: file.lengthSync()));
    }
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تجهيز التطبيقات')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التطبيقات')),
        bottomNavigationBar: selected.isEmpty ? null : SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(onPressed: prepare, icon: const Icon(Icons.send_rounded), label: Text('إرسال ${selected.length} تطبيق')))),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  final app = apps[index];
                  final isSelected = selected.contains(app.packageName);
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.apps_rounded)),
                      title: Text(app.name),
                      subtitle: Text(app.packageName),
                      trailing: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            selected.remove(app.packageName);
                          } else {
                            selected.add(app.packageName);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
