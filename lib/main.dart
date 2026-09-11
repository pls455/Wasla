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
  return raw
      .map((item) => AppItem.fromMap(Map<String, dynamic>.from(item as Map)))
      .toList();
}

Future<String?> exportApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return appsChannel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatSpeed(double bytesPerSecond) {
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

String formatDuration(Duration? value) {
  if (value == null) return '--:--';
  final seconds = value.inSeconds.clamp(0, 999999);
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

void main() => runApp(const WaslaApp());

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
    final brightness = themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: brightness,
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
        onTheme: () => setState(() {
          themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
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
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (!mounted || picked == null || picked.files.isEmpty) return;

    final files = <TransferFile>[];
    for (final item in picked.files) {
      final path = item.path;
      if (path != null) {
        files.add(TransferFile(
          name: item.name,
          path: path,
          size: File(path).lengthSync(),
        ));
      }
    }
    if (files.isEmpty || !mounted) return;

    await Navigator.push(
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const Text('نقل مباشر.', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('أرسل ملفاتك محليًا بين الأجهزة بدون خادم وسيط.', style: TextStyle(color: muted)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: MainAction(
                    icon: Icons.send_rounded,
                    title: 'إرسال',
                    subtitle: 'ملفات وتطبيقات',
                    onTap: () => sendFiles(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MainAction(
                    icon: Icons.download_rounded,
                    title: 'استقبال',
                    subtitle: 'انتظر جهازًا',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceivePage(storage: widget.storage, discovery: widget.discovery),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نقل محلي مباشر', style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 3),
                          Text('البيانات تنتقل بين الجهازين مباشرة.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('الأجهزة القريبة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${devices.length}'),
              ],
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Icon(Icons.devices_other_rounded, size: 42),
                      const SizedBox(height: 10),
                      const Text('لا توجد أجهزة قريبة حاليًا.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('تأكد أن الجهازين على الشبكة نفسها.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
                    ],
                  ),
                ),
              )
            else
              for (final device in devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone_android_rounded)),
                      title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(device.host),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => sendFiles(target: device),
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppPage(storage: widget.storage, discovery: widget.discovery),
                ),
              ),
              icon: const Icon(Icons.apps_rounded),
              label: const Text('إرسال التطبيقات المثبتة'),
            ),
          ],
        ),
      ),
    );
  }
}

class MainAction extends StatelessWidget {
  const MainAction({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 36),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

    setState(() {
      sending = true;
      status = 'جاري الاتصال...';
      progress = null;
    });

    final socket = await widget.discovery.connect(device);
    if (socket == null) {
      if (mounted) {
        setState(() {
          sending = false;
          status = 'تعذر الاتصال';
        });
      }
      return;
    }

    try {
      final name = await widget.storage.deviceName();
      await transfer.send(
        socket: socket,
        senderName: name,
        files: widget.files,
        onProgress: (value) {
          if (mounted) {
            setState(() {
              progress = value;
              status = value.status;
            });
          }
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
    final p = progress;
    final fraction = p == null || p.total == 0 ? 0.0 : (p.bytes / p.total).clamp(0.0, 1.0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إرسال', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.folder_copy_rounded, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.files.length} ملف', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(widget.files.map((f) => '${f.name} • ${formatBytes(f.size)}').join('\n')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (selected == null) ...[
              const Text('اختر الجهاز المستلم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد أجهزة متاحة الآن.')))
              else
                for (final device in devices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.phone_android_rounded)),
                        title: Text(device.name),
                        subtitle: Text(device.host),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => setState(() => selected = device),
                      ),
                    ),
                  ),
            ] else
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.check_rounded)),
                  title: Text(selected!.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(selected!.host),
                  trailing: TextButton(
                    onPressed: sending ? null : () => setState(() => selected = null),
                    child: const Text('تغيير'),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            if (p != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(children: [const Text('حالة النقل', style: TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('${(fraction * 100).toStringAsFixed(0)}%')]),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: fraction, minHeight: 9),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _Metric(label: 'السرعة', value: formatSpeed(p.speed), icon: Icons.speed_rounded)),
                          Expanded(child: _Metric(label: 'المتبقي', value: formatDuration(p.eta), icon: Icons.timer_outlined)),
                          Expanded(child: _Metric(label: 'المنقول', value: formatBytes(p.bytes), icon: Icons.swap_horiz_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(status, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )
            else
              Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(status, textAlign: TextAlign.center))),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: selected == null || sending ? null : startSend,
              icon: Icon(sending ? Icons.sync_rounded : Icons.send_rounded),
              label: Text(sending ? 'جاري الإرسال...' : 'ابدأ الإرسال'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
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
    if (busy) {
      socket.destroy();
      return;
    }
    busy = true;
    final reader = SocketReader(socket);
    try {
      final offer = await reader.readLine();
      if (offer['type'] != 'offer') throw StateError('طلب نقل غير صالح');
      final list = offer['files'] as List<dynamic>? ?? const [];
      final files = <TransferFile>[];
      for (final item in list) {
        final map = Map<String, dynamic>.from(item as Map);
        files.add(TransferFile(
          name: map['name'] as String,
          path: '',
          size: (map['size'] as num).toInt(),
          hash: map['hash'] as String?,
        ));
      }

      if (mounted) {
        setState(() {
          status = 'استقبال ${files.length} ملف';
          progress = null;
        });
      }

      await TransferService(widget.storage).receive(
        socket: socket,
        files: files,
        reader: reader,
        onProgress: (value) {
          if (mounted) {
            setState(() {
              progress = value;
              status = value.status;
            });
          }
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
    final p = progress;
    final fraction = p == null || p.total == 0 ? 0.0 : (p.bytes / p.total).clamp(0.0, 1.0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استقبال', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: p == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_tethering_rounded, size: 76),
                      const SizedBox(height: 22),
                      Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text('أبقِ هذه الشاشة مفتوحة حتى يتصل الجهاز الآخر.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  )
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(fraction * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(value: fraction, minHeight: 10),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(child: _Metric(label: 'السرعة', value: formatSpeed(p.speed), icon: Icons.speed_rounded)),
                              Expanded(child: _Metric(label: 'المتبقي', value: formatDuration(p.eta), icon: Icons.timer_outlined)),
                              Expanded(child: _Metric(label: 'المنقول', value: formatBytes(p.bytes), icon: Icons.download_rounded)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(status, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
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
  void initState() {
    super.initState();
    loadApps();
  }

  Future<void> loadApps() async {
    try {
      final value = await installedApps();
      if (mounted) setState(() { apps = value; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendSelected() async {
    final files = <TransferFile>[];
    for (final app in apps.where((item) => selected.contains(item.packageName))) {
      final path = await exportApp(app.packageName);
      if (path != null && File(path).existsSync()) {
        files.add(TransferFile(name: '${app.name}.apk', path: path, size: File(path).lengthSync()));
      }
    }
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تجهيز التطبيقات المحددة.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التطبيقات', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            if (apps.isNotEmpty)
              IconButton(
                onPressed: () => setState(() {
                  if (selected.length == apps.length) {
                    selected.clear();
                  } else {
                    selected.addAll(apps.map((app) => app.packageName));
                  }
                }),
                icon: const Icon(Icons.select_all_rounded),
              ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : apps.isEmpty
                ? const Center(child: Text('لا توجد تطبيقات قابلة للمشاركة.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      final checked = selected.contains(app.packageName);
                      return Card(
                        child: CheckboxListTile(
                          value: checked,
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              selected.add(app.packageName);
                            } else {
                              selected.remove(app.packageName);
                            }
                          }),
                          secondary: const CircleAvatar(child: Icon(Icons.android_rounded)),
                          title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(formatBytes(app.size)),
                        ),
                      );
                    },
                  ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: selected.isEmpty ? null : sendSelected,
              icon: const Icon(Icons.send_rounded),
              label: Text('إرسال ${selected.length} تطبيق'),
            ),
          ),
        ),
      ),
    );
  }
}
