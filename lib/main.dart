import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/models/transfer_models.dart';
import 'core/services/discovery_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/transfer_service.dart';

const _channel = MethodChannel('com.wasla/apps');

Future<List<AppItem>> loadInstalledApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await _channel.invokeMethod<List<dynamic>>('listApps') ?? const [];
  return raw
      .map((e) => AppItem.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
}

Future<String?> exportInstalledApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return _channel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

class AppItem {
  const AppItem({
    required this.packageName,
    required this.name,
    required this.size,
    this.iconBase64,
  });

  final String packageName;
  final String name;
  final int size;
  final String? iconBase64;

  factory AppItem.fromMap(Map<String, dynamic> m) => AppItem(
        packageName: m['packageName'] as String,
        name: m['name'] as String,
        size: (m['size'] as num?)?.toInt() ?? 0,
        iconBase64: m['icon'] as String?,
      );
}

void main() => runApp(const WaslaApp());

class WaslaApp extends StatefulWidget {
  const WaslaApp({super.key});

  @override
  State<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends State<WaslaApp> {
  final storage = StorageService();
  late final discovery = DiscoveryService(storage);
  ThemeMode mode = ThemeMode.dark;

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وصلة | Wasla',
      themeMode: mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(
        storage: storage,
        discovery: discovery,
        onToggleTheme: () => setState(
          () => mode = mode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF08090D) : const Color(0xFFF7F7FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.storage,
    required this.discovery,
    required this.onToggleTheme,
  });

  final StorageService storage;
  final DiscoveryService discovery;
  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NearbyDevice> devices = const [];
  String deviceName = 'هاتف وصلة';

  @override
  void initState() {
    super.initState();
    widget.storage.deviceName().then((v) {
      if (mounted) setState(() => deviceName = v);
    });
    widget.discovery.devices.listen((v) {
      if (mounted) setState(() => devices = v);
    });
  }

  void _receive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceivePage(
          storage: widget.storage,
          discovery: widget.discovery,
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
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'وصلة',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
              ),
              Text(
                'Wasla',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: widget.onToggleTheme,
              tooltip: 'المظهر',
              icon: const Icon(Icons.contrast_rounded),
            ),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(storage: widget.storage),
                ),
              ),
              tooltip: 'الإعدادات',
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => widget.discovery.start(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
            children: [
              const Text(
                'أرسل ملفاتك مباشرة.',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'بدون خادم وسيط. وصلة تختار أفضل اتصال متاح.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: _PrimaryAction(
                      icon: Icons.arrow_upward_rounded,
                      title: 'إرسال',
                      subtitle: 'ملفات أو تطبيقات',
                      onTap: _showSendOptions,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryAction(
                      icon: Icons.arrow_downward_rounded,
                      title: 'استقبال',
                      subtitle: 'انتظر طلبًا',
                      onTap: _receive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Icon(Icons.radar_rounded, size: 21),
                  const SizedBox(width: 9),
                  const Text(
                    'الأجهزة القريبة',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text('${devices.length}'),
                ],
              ),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                const _EmptyNearby()
              else
                ...devices.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DeviceTile(
                      device: d,
                      onTap: () => _showSendOptions(target: d),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              _PrivacyStrip(deviceName: deviceName),
            ],
          ),
        ),
      ),
    );
  }

  void _showSendOptions({NearbyDevice? target}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheet) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ماذا تريد أن ترسل؟',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(target == null ? 'اختر المحتوى ثم اختر الجهاز.' : 'إلى ${target.name}'),
              const SizedBox(height: 18),
              _SheetAction(
                icon: Icons.folder_rounded,
                title: 'ملفات',
                subtitle: 'صور، فيديو، مستندات وغيرها',
                onTap: () async {
                  Navigator.pop(sheet);
                  final picked = await FilePicker.pickFiles(allowMultiple: true);
                  if (!mounted || picked.isEmpty) return;
                  final files = picked.files
                      .where((f) => f.path != null)
                      .map(
                        (f) => TransferFile(
                          name: f.name,
                          path: f.path!,
                          size: f.size,
                        ),
                      )
                      .toList();
                  if (files.isNotEmpty && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SendPage(
                          storage: widget.storage,
                          discovery: widget.discovery,
                          files: files,
                          deviceName: deviceName,
                          target: target,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: Icons.apps_rounded,
                title: 'تطبيقات',
                subtitle: 'اختر تطبيقات مثبتة على جهازك',
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppPickerPage(
                        onReady: (files) => _openSendTo(files, target),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SheetAction(
                icon: Icons.link_rounded,
                title: 'نص أو رابط',
                subtitle: 'ضمن المرحلة التالية',
                onTap: () {
                  Navigator.pop(sheet);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('مشاركة النص والروابط ضمن المرحلة التالية.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSendTo(List<TransferFile> files, NearbyDevice? target) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendPage(
          storage: widget.storage,
          discovery: widget.discovery,
          files: files,
          deviceName: deviceName,
          target: target,
        ),
      ),
    );
  }
}

class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.onReady});

  final void Function(List<TransferFile>) onReady;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppItem> apps = const [];
  final selected = <String>{};
  bool loading = true;
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await loadInstalledApps();
      v.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          apps = v;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = apps
        .where(
          (a) =>
              a.name.toLowerCase().contains(query.toLowerCase()) ||
              a.packageName.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'التطبيقات',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (selected.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text('${selected.length} محدد'),
                ),
              ),
          ],
        ),
        bottomNavigationBar: selected.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: FilledButton.icon(
                    onPressed: _prepare,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: Text('إرسال ${selected.length} تطبيق'),
                  ),
                ),
              ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                children: [
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن تطبيق',
                      prefixIcon: Icon(Icons.search_rounded),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('${shown.length} تطبيق متاح'),
                  const SizedBox(height: 8),
                  ...shown.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AppTile(
                        app: a,
                        selected: selected.contains(a.packageName),
                        onTap: () => setState(
                          () => selected.contains(a.packageName)
                              ? selected.remove(a.packageName)
                              : selected.add(a.packageName),
                        ),
                      ),
                    ),
                  ),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 70),
                      child: Center(child: Text('لم نجد تطبيقًا بهذا الاسم')),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _prepare() async {
    final chosen = apps.where((a) => selected.contains(a.packageName)).toList();
    final files = <TransferFile>[];

    for (final app in chosen) {
      final path = await exportInstalledApp(app.packageName);
      if (path != null && File(path).existsSync()) {
        final file = File(path);
        files.add(
          TransferFile(
            name: '${app.name}.apk',
            path: path,
            size: file.lengthSync(),
          ),
        );
      }
    }

    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تجهيز التطبيقات المحددة للإرسال.')),
      );
      return;
    }

    Navigator.pop(context);
    widget.onReady(files);
  }
}

class SendPage extends StatefulWidget {
  const SendPage({
    super.key,
    required this.storage,
    required this.discovery,
    required this.files,
    required this.deviceName,
    this.target,
  });

  final StorageService storage;
  final DiscoveryService discovery;
  final List<TransferFile> files;
  final String deviceName;
  final NearbyDevice? target;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  NearbyDevice? selected;
  TransferProgress? progress;
  bool running = false;
  String status = 'اختر جهازًا';

  @override
  void initState() {
    super.initState();
    selected = widget.target;
    if (selected != null) _start();
  }

  Future<void> _start() async {
    if (running || selected == null) return;

    setState(() {
      running = true;
      status = 'جاري الاتصال...';
    });

    final socket = await widget.discovery.connect(selected!);
    if (socket == null) {
      if (mounted) {
        setState(() {
          running = false;
          status = 'تعذر الاتصال بالجهاز';
        });
      }
      return;
    }

    try {
      await TransferService(widget.storage).send(
        socket: socket,
        senderName: widget.deviceName,
        files: widget.files,
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
      );

      await widget.storage.addHistory(
        TransferRecord(
          id: DateTime.now().toIso8601String(),
          direction: TransferDirection.sent,
          device: selected!.name,
          totalBytes: widget.files.fold(0, (a, b) => a + b.size),
          completedBytes: widget.files.fold(0, (a, b) => a + b.size),
          status: 'success',
          createdAt: DateTime.now(),
        ),
      );

      if (mounted) setState(() => status = 'تم الإرسال والتحقق');
    } catch (e) {
      if (mounted) setState(() => status = _humanError(e));
    } finally {
      await socket.close();
      if (mounted) setState(() => running = false);
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
            _TransferCard(
              progress: progress,
              files: widget.files,
              status: status,
            ),
            const SizedBox(height: 18),
            if (selected == null)
              StreamBuilder<List<NearbyDevice>>(
                stream: widget.discovery.devices,
                initialData: const [],
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const <NearbyDevice>[];
                  return Column(
                    children: list
                        .map(
                          (d) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DeviceTile(
                              device: d,
                              onTap: () {
                                setState(() => selected = d);
                                _start();
                              },
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            if (selected != null && !running && progress == null)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('بدء النقل'),
              ),
          ],
        ),
      ),
    );
  }
}

class ReceivePage extends StatefulWidget {
  const ReceivePage({
    super.key,
    required this.storage,
    required this.discovery,
  });

  final StorageService storage;
  final DiscoveryService discovery;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  ServerSocket? server;
  Socket? pending;
  SocketReader? reader;
  Map<String, dynamic>? offer;
  TransferProgress? progress;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    server = await widget.discovery.transferServer;
    server?.listen((socket) async {
      if (busy || pending != null) {
        await socket.close();
        return;
      }

      pending = socket;
      reader = SocketReader(socket);
      try {
        final first = await reader!.readLine();
        if (first['type'] == 'offer' && mounted) {
          setState(() => offer = first);
        }
      } catch (_) {
        await socket.close();
      }
    });
  }

  Future<void> _accept() async {
    final socket = pending;
    final input = reader;
    final o = offer;
    if (socket == null || input == null || o == null) return;

    setState(() => busy = true);

    final rawFiles = o['files'] as List? ?? const [];
    final files = rawFiles
        .map(
          (e) => TransferFile(
            name: e['name'] as String,
            path: '',
            size: (e['size'] as num).toInt(),
            hash: e['hash'] as String?,
          ),
        )
        .toList();

    try {
      await TransferService(widget.storage).receive(
        socket: socket,
        reader: input,
        files: files,
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
      );

      await widget.storage.addHistory(
        TransferRecord(
          id: DateTime.now().toIso8601String(),
          direction: TransferDirection.received,
          device: o['sender']?.toString() ?? 'جهاز',
          totalBytes: files.fold(0, (a, b) => a + b.size),
          completedBytes: files.fold(0, (a, b) => a + b.size),
          status: 'success',
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_humanError(e))),
        );
      }
    } finally {
      await socket.close();
      if (mounted) {
        setState(() {
          busy = false;
          pending = null;
          reader = null;
          offer = null;
        });
      }
    }
  }

  Future<void> _reject() async {
    await pending?.close();
    if (mounted) {
      setState(() {
        pending = null;
        reader = null;
        offer = null;
      });
    }
  }

  @override
  void dispose() {
    server?.close();
    pending?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استقبال')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (offer != null)
              _IncomingCard(
                offer: offer!,
                onAccept: _accept,
                onReject: _reject,
              ),
            if (offer == null && progress == null) const _EmptyReceive(),
            if (progress != null)
              _TransferCard(
                progress: progress,
                files: const [],
                status: progress!.status,
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.storage});

  final StorageService storage;

  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  late final TextEditingController c = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.storage.deviceName().then((v) {
      if (mounted) c.text = v;
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: c,
              decoration: const InputDecoration(
                labelText: 'اسم الجهاز',
                prefixIcon: Icon(Icons.devices_other_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await widget.storage.setDeviceName(c.text);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
            const SizedBox(height: 24),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('الخصوصية'),
              subtitle: Text(
                'النقل يتم مباشرة بين الأجهزة. لا نرفع الملفات إلى خادم مركزي.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 148,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [scheme.primaryContainer, scheme.primary.withOpacity(.78)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 31),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            Text(
              subtitle,
              style: TextStyle(
                color: scheme.onPrimaryContainer.withOpacity(.75),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 148,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: scheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 31),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            Text(
              subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      subtitle: Text(subtitle),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final NearbyDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CircleAvatar(radius: 24, child: Icon(Icons.devices_rounded)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      'جاهز للاتصال',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNearby extends StatelessWidget {
  const _EmptyNearby();

  @override
  Widget build(BuildContext c) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(c).dividerColor),
      ),
      child: const Column(
        children: [
          Icon(Icons.wifi_find_rounded, size: 38),
          SizedBox(height: 8),
          Text('لا توجد أجهزة قريبة', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 5),
          Text(
            'افتح وصلة على الجهاز الآخر وتأكد من الاتصال بالشبكة نفسها.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext c) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(c).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذا الجهاز: $deviceName\nالنقل محلي ومباشر.',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.progress,
    required this.files,
    required this.status,
  });

  final TransferProgress? progress;
  final List<TransferFile> files;
  final String status;

  @override
  Widget build(BuildContext c) {
    final p = progress;
    final ratio = p == null || p.total == 0 ? 0.0 : p.bytes / p.total;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Theme.of(c).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            p?.status.contains('اكتمل') == true
                ? Icons.check_circle_rounded
                : Icons.bolt_rounded,
            size: 38,
          ),
          const SizedBox(height: 14),
          Text(status, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${files.length} ملف • ${_fmt(files.fold(0, (a, b) => a + b.size))}',
              ),
            ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: p == null ? null : ratio,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${_fmt(p.bytes)} / ${_fmt(p.total)} • ${_fmt(p.speed.round())}/ث${p.eta == null ? '' : ' • ${p.eta!.inSeconds} ث تقريباً'}',
                style: TextStyle(
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.offer,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> offer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext c) {
    final files = offer['files'] as List? ?? const [];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Theme.of(c).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.file_download_outlined, size: 36),
          const SizedBox(height: 12),
          const Text('طلب استقبال', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text('${offer['sender'] ?? 'جهاز قريب'} يريد إرسال ${files.length} ملف'),
          const SizedBox(height: 12),
          ...files.map(
            (f) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(f['name']?.toString() ?? 'ملف'),
              subtitle: Text(_fmt((f['size'] as num?)?.toInt() ?? 0)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: onReject, child: const Text('رفض')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: onAccept, child: const Text('استقبال')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyReceive extends StatelessWidget {
  const _EmptyReceive();

  @override
  Widget build(BuildContext c) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 65),
          SizedBox(height: 15),
          Text('جاهز للاستقبال', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text(
            'عندما يرسل إليك جهاز قريب سيظهر الطلب هنا قبل بدء النقل.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final AppItem app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    ImageProvider? image;
    try {
      if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
        image = MemoryImage(base64Decode(app.iconBase64!));
      }
    } catch (_) {}

    final scheme = Theme.of(c).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  image: image == null
                      ? null
                      : DecorationImage(image: image, fit: BoxFit.cover),
                  color: scheme.surface,
                ),
                child: image == null ? const Icon(Icons.apps_rounded) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _fmt(app.size),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Checkbox(value: selected, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return '${n < 10 && i > 0 ? n.toStringAsFixed(1) : n.round()} ${units[i]}';
}

String _humanError(Object e) {
  final s = e.toString().replaceFirst('Bad state: ', '');
  if (s.contains('لم يتم قبول')) return 'تم رفض عملية النقل.';
  if (s.contains('انقطع')) return 'انقطع الاتصال. يمكنك المحاولة مجددًا.';
  if (s.contains('التحقق')) return 'تعذر التحقق من الملف بعد النقل.';
  return s;
}
