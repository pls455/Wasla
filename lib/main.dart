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

class AppItem {
  const AppItem({required this.packageName, required this.name, required this.size, this.icon});
  final String packageName;
  final String name;
  final int size;
  final String? icon;
  factory AppItem.fromMap(Map<String, dynamic> map) => AppItem(
    packageName: map['packageName'] as String? ?? '',
    name: map['name'] as String? ?? 'تطبيق',
    size: (map['size'] as num?)?.toInt() ?? 0,
    icon: map['icon'] as String?,
  );
}

Future<List<AppItem>> installedApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await appsChannel.invokeMethod<List<dynamic>>('listApps') ?? const [];
  return raw.map((e) => AppItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
}

Future<String?> exportApp(String packageName) async {
  if (!Platform.isAndroid) return null;
  return appsChannel.invokeMethod<String>('exportApp', {'packageName': packageName});
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatSpeed(double value) => '${(value / (1024 * 1024)).toStringAsFixed(1)} MB/s';

String formatDuration(Duration? value) {
  if (value == null) return '--:--';
  final seconds = value.inSeconds.clamp(0, 999999).toInt();
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
  @override Widget build(BuildContext context) {
    final dark = themeMode == ThemeMode.dark;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF7357FF), brightness: dark ? Brightness.dark : Brightness.light);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وصلة',
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface),
      home: HomePage(storage: storage, discovery: discovery, onTheme: () => setState(() => themeMode = dark ? ThemeMode.light : ThemeMode.dark)),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.storage, required this.discovery, required this.onTheme});
  final StorageService storage; final DiscoveryService discovery; final VoidCallback onTheme;
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NearbyDevice> devices = const [];
  StreamSubscription<List<NearbyDevice>>? sub;
  String deviceName = 'هاتف وصلة';
  @override void initState() { super.initState(); sub = widget.discovery.devices.listen((v) { if (mounted) setState(() => devices = v); }); _load(); }
  Future<void> _load() async { final n = await widget.storage.deviceName(); if (mounted) setState(() => deviceName = n); }
  @override void dispose() { sub?.cancel(); super.dispose(); }

  Future<void> pickAndSend({NearbyDevice? target}) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (!mounted || result == null) return;
    final files = <TransferFile>[];
    for (final f in result.files) { if (f.path != null) files.add(TransferFile(name: f.name, path: f.path!, size: File(f.path!).lengthSync())); }
    if (files.isEmpty || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SendPage(storage: widget.storage, discovery: widget.discovery, files: files, target: target)));
  }

  void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('وصلة', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: widget.onTheme, icon: const Icon(Icons.contrast_rounded))]),
        body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
          Text('نقل مباشر.', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: c.primary)),
          const Text('شارك ملفاتك بين أجهزتك بسرعة، محليًا وبدون خادم وسيط.'),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: ActionCard(icon: Icons.send_rounded, title: 'إرسال', subtitle: 'ملفات، صور، فيديو', onTap: () => pickAndSend())), const SizedBox(width: 12), Expanded(child: ActionCard(icon: Icons.download_rounded, title: 'استقبال', subtitle: 'انتظر اتصالًا', onTap: () => open(ReceivePage(storage: widget.storage, discovery: widget.discovery))))]),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(Icons.wifi_rounded, color: c.primary), const SizedBox(width: 12), Expanded(child: Text('${devices.length} جهاز قريب • $deviceName', style: const TextStyle(fontWeight: FontWeight.w700))), IconButton(onPressed: () => open(QrPage(storage: widget.storage, discovery: widget.discovery)), icon: const Icon(Icons.qr_code_rounded))]))),
          const SizedBox(height: 18),
          SectionTitle('الأجهزة القريبة', action: TextButton.icon(onPressed: () => open(ManualConnectPage(storage: widget.storage, discovery: widget.discovery)), icon: const Icon(Icons.add_link_rounded), label: const Text('إضافة يدويًا'))),
          if (devices.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [const Icon(Icons.devices_other_rounded, size: 44), const SizedBox(height: 8), const Text('لا توجد أجهزة مكتشفة الآن', style: TextStyle(fontWeight: FontWeight.w800)), const Text('استخدم QR أو الاتصال اليدوي إذا كانت الشبكة تمنع البث.', textAlign: TextAlign.center)])))
          else for (final d in devices) Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.phone_android_rounded)), title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(d.host), trailing: const Icon(Icons.chevron_left_rounded), onTap: () => pickAndSend(target: d))),
          const SizedBox(height: 12),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.9, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
            SmallAction(icon: Icons.apps_rounded, label: 'التطبيقات', onTap: () => open(AppPage(storage: widget.storage, discovery: widget.discovery))),
            SmallAction(icon: Icons.history_rounded, label: 'سجل النقل', onTap: () => open(HistoryPage(storage: widget.storage))),
            SmallAction(icon: Icons.qr_code_scanner_rounded, label: 'مسح QR', onTap: () => open(ScanPage(storage: widget.storage, discovery: widget.discovery))),
            SmallAction(icon: Icons.settings_rounded, label: 'الإعدادات', onTap: () => open(SettingsPage(storage: widget.storage))),
          ]),
        ]),
      ),
    );
  }
}

class ActionCard extends StatelessWidget { const ActionCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap}); final IconData icon; final String title, subtitle; final VoidCallback onTap; @override Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [Icon(icon, size: 38), const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])))); }
class SmallAction extends StatelessWidget { const SmallAction({super.key, required this.icon, required this.label, required this.onTap}); final IconData icon; final String label; final VoidCallback onTap; @override Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(width: 8), Text(label, style: const TextStyle(fontWeight: FontWeight.w800))]))); }
class SectionTitle extends StatelessWidget { const SectionTitle(this.title, {super.key, this.action}); final String title; final Widget? action; @override Widget build(BuildContext context) => Row(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const Spacer(), if (action != null) action!]); }

class SendPage extends StatefulWidget { const SendPage({super.key, required this.storage, required this.discovery, required this.files, this.target}); final StorageService storage; final DiscoveryService discovery; final List<TransferFile> files; final NearbyDevice? target; @override State<SendPage> createState() => _SendPageState(); }
class _SendPageState extends State<SendPage> {
  NearbyDevice? selected; List<NearbyDevice> devices = const []; TransferProgress? progress; bool sending = false; String status = 'اختر جهازًا'; StreamSubscription<List<NearbyDevice>>? sub;
  @override void initState() { super.initState(); selected = widget.target; sub = widget.discovery.devices.listen((v) { if (mounted) setState(() => devices = v); }); }
  @override void dispose() { sub?.cancel(); super.dispose(); }
  Future<void> send() async {
    final d = selected; if (d == null || sending) return;
    final ok = await confirm(context, 'تأكيد الإرسال', 'سيتم إرسال ${widget.files.length} عنصر إلى ${d.name}.'); if (!ok || !mounted) return;
    setState(() { sending = true; status = 'جاري الاتصال...'; });
    final socket = await widget.discovery.connect(d);
    if (socket == null) { if (mounted) setState(() { sending = false; status = 'تعذر الاتصال'; }); return; }
    try {
      final service = TransferService(widget.storage); final sender = await widget.storage.deviceName();
      await service.send(socket: socket, senderName: sender, files: widget.files, onProgress: (p) { if (mounted) setState(() { progress = p; status = p.status; }); });
      await widget.storage.addHistory(TransferRecord(id: DateTime.now().microsecondsSinceEpoch.toString(), direction: TransferDirection.sent, device: d.name, totalBytes: widget.files.fold(0, (a,b)=>a+b.size), completedBytes: widget.files.fold(0, (a,b)=>a+b.size), status: 'نجح', createdAt: DateTime.now()));
    } catch (e) { if (mounted) setState(() => status = e.toString().replaceFirst('Bad state: ', '')); } finally { socket.destroy(); if (mounted) setState(() => sending = false); }
  }
  @override Widget build(BuildContext context) { final p = progress; final fraction = p == null || p.total == 0 ? 0.0 : (p.bytes / p.total).clamp(0.0, 1.0).toDouble(); return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('إرسال')), body: ListView(padding: const EdgeInsets.all(18), children: [Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('${widget.files.length} عنصر • ${formatBytes(widget.files.fold(0, (a,b)=>a+b.size))}'))), const SizedBox(height: 14), if (selected == null) ...[const Text('اختر الجهاز', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), for (final d in devices) Card(child: ListTile(leading: const Icon(Icons.phone_android), title: Text(d.name), subtitle: Text(d.host), onTap: () => setState(() => selected = d)))] else Card(child: ListTile(leading: const Icon(Icons.verified_user_rounded), title: Text(selected!.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(selected!.host), trailing: TextButton(onPressed: sending ? null : () => setState(() => selected = null), child: const Text('تغيير')))), const SizedBox(height: 18), if (p != null) ...[LinearProgressIndicator(value: fraction), const SizedBox(height: 12), Text('${(fraction*100).toStringAsFixed(0)}% • ${formatSpeed(p.speed)} • ETA ${formatDuration(p.eta)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))], const SizedBox(height: 12), Text(status, textAlign: TextAlign.center), const SizedBox(height: 18), FilledButton.icon(onPressed: selected == null || sending ? null : send, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'جارٍ الإرسال' : 'ابدأ الإرسال'))])); }
}

class ReceivePage extends StatefulWidget { const ReceivePage({super.key, required this.storage, required this.discovery}); final StorageService storage; final DiscoveryService discovery; @override State<ReceivePage> createState() => _ReceivePageState(); }
class _ReceivePageState extends State<ReceivePage> {
  ServerSocket? server; bool waiting = false; String status = 'جاهز للاستقبال'; TransferProgress? progress;
  @override void initState() { super.initState(); _start(); }
  Future<void> _start() async { server = await widget.discovery.transferServer; if (mounted) setState(() => waiting = true); _acceptLoop(); }
  Future<void> _acceptLoop() async { final s = server; if (s == null) return; await for (final socket in s) { if (!mounted) { socket.destroy(); return; } if (!waiting) { socket.destroy(); continue; } setState(() { waiting = false; status = 'طلب اتصال وارد...'; }); await _handle(socket); if (mounted) { setState(() { waiting = true; status = 'جاهز لجهاز آخر'; }); } } }
  Future<void> _handle(Socket socket) async { try { final reader = SocketReader(socket); final offer = await reader.readLine(); if (offer['type'] != 'offer') throw StateError('طلب غير صالح'); final sender = offer['sender'] as String? ?? 'جهاز'; final list = (offer['files'] as List).map((e) { final m = Map<String,dynamic>.from(e as Map); return TransferFile(name: m['name'], path: '', size: (m['size'] as num).toInt(), hash: m['hash']); }).toList(); if (!mounted) { socket.destroy(); return; } final ok = await confirm(context, 'طلب استقبال', '$sender يريد إرسال ${list.length} عنصر (${formatBytes(list.fold(0,(a,b)=>a+b.size))}).\nتحقق من رمز الجلسة: ${offer['code'] ?? '------'}'); if (!ok) { socket.write('{"type":"reject"}\n'); await socket.flush(); socket.destroy(); return; } final service = TransferService(widget.storage); await service.receive(socket: socket, files: list, reader: reader, onProgress: (p) { if (mounted) setState(() { progress = p; status = p.status; }); }); await widget.storage.addHistory(TransferRecord(id: DateTime.now().microsecondsSinceEpoch.toString(), direction: TransferDirection.received, device: sender, totalBytes: list.fold(0,(a,b)=>a+b.size), completedBytes: list.fold(0,(a,b)=>a+b.size), status: 'نجح', createdAt: DateTime.now())); } catch (e) { if (mounted) setState(() => status = e.toString().replaceFirst('Bad state: ', '')); } finally { socket.destroy(); } }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('استقبال')), body: ListView(padding: const EdgeInsets.all(18), children: [Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(waiting ? Icons.wifi_find_rounded : Icons.downloading_rounded, size: 54), const SizedBox(height: 12), Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(waiting ? 'أبقِ هذه الصفحة مفتوحة وانتظر طلب الإرسال.' : 'جارٍ معالجة النقل...')]))), if (progress != null) ...[const SizedBox(height: 18), LinearProgressIndicator(value: progress!.total == 0 ? 0 : progress!.bytes / progress!.total), const SizedBox(height: 10), Text('${formatSpeed(progress!.speed)} • ${formatDuration(progress!.eta)}', textAlign: TextAlign.center)] ]));
}

class AppPage extends StatefulWidget { const AppPage({super.key, required this.storage, required this.discovery}); final StorageService storage; final DiscoveryService discovery; @override State<AppPage> createState()=>_AppPageState(); }
class _AppPageState extends State<AppPage> { List<AppItem> apps=[]; final selected=<String>{}; bool loading=true; @override void initState(){super.initState(); _load();} Future<void> _load() async { try { apps=await installedApps(); } finally { if(mounted)setState(()=>loading=false); } } Future<void> sendApps(){ final chosen=apps.where((a)=>selected.contains(a.packageName)).toList(); return _send(chosen); } Future<void> _send(List<AppItem> chosen) async { if(chosen.isEmpty)return; final result=await FilePicker.platform.pickFiles(allowMultiple:false); if(result!=null){} final files=<TransferFile>[]; for(final a in chosen){final p=await exportApp(a.packageName); if(p!=null) files.add(TransferFile(name:'${a.name}.apk',path:p,size:File(p).lengthSync()));} if(!mounted||files.isEmpty)return; Navigator.push(context,MaterialPageRoute(builder:(_)=>SendPage(storage:widget.storage,discovery:widget.discovery,files:files))); } @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('التطبيقات المثبتة')),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[Text('${apps.length} تطبيق',style:const TextStyle(fontWeight:FontWeight.w800)),...apps.map((a)=>Card(child:CheckboxListTile(value:selected.contains(a.packageName),onChanged:(v)=>setState(()=>v==true?selected.add(a.packageName):selected.remove(a.packageName)),title:Text(a.name),subtitle:Text('${formatBytes(a.size)} • ${a.packageName}'),secondary:const Icon(Icons.android_rounded)))),FilledButton.icon(onPressed:selected.isEmpty?null:sendApps,icon:const Icon(Icons.send),label:Text('إرسال ${selected.length} تطبيق'))])); }

class QrPage extends StatefulWidget { const QrPage({super.key, required this.storage, required this.discovery}); final StorageService storage; final DiscoveryService discovery; @override State<QrPage> createState()=>_QrPageState(); }
class _QrPageState extends State<QrPage>{ String payload='جارٍ التحضير...'; @override void initState(){super.initState();_make();} Future<void> _make() async { final name=await widget.storage.deviceName(); final server=await widget.discovery.transferServer; final interfaces=await NetworkInterface.list(type:InternetAddressType.IPv4,includeLinkLocal:false); final ip=interfaces.expand((i)=>i.addresses).map((a)=>a.address).firstWhere((a)=>!a.startsWith('127.'),orElse:()=> '127.0.0.1'); if(mounted)setState(()=>payload=jsonEncode({'v':1,'host':ip,'port':server?.port,'name':name})); } @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('QR للاتصال')),body:Center(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(28),children:[const Text('امسح هذا الرمز من الجهاز الآخر',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:20),if(payload!='جارٍ التحضير...')Center(child:QrImageView(data:'WASLA:$payload',size:270,backgroundColor:Colors.white,padding:const EdgeInsets.all(18))),const SizedBox(height:18),SelectableText(payload,textAlign:TextAlign.center),const SizedBox(height:12),const Text('الاتصال محلي فقط. لا يتم إرسال البيانات إلى خادم وسيط.',textAlign:TextAlign.center)]))); }

class ScanPage extends StatelessWidget { const ScanPage({super.key, required this.storage, required this.discovery}); final StorageService storage; final DiscoveryService discovery; @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('مسح QR')),body:MobileScanner(onDetect:(capture){if(capture.barcodes.isEmpty)return;final raw=capture.barcodes.first.rawValue;if(raw==null||!raw.startsWith('WASLA:'))return;try{final m=jsonDecode(raw.substring(6)) as Map<String,dynamic>;final d=NearbyDevice(id:'qr-${m['host']}',name:m['name']??'جهاز QR',host:m['host'],port:(m['port'] as num).toInt());Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>ManualSendPage(storage:storage,discovery:discovery,target:d)));}catch(_){}}})); }

class ManualConnectPage extends StatefulWidget { const ManualConnectPage({super.key, required this.storage, required this.discovery}); final StorageService storage; final DiscoveryService discovery; @override State<ManualConnectPage> createState()=>_ManualConnectPageState(); }
class _ManualConnectPageState extends State<ManualConnectPage>{final host=TextEditingController();final port=TextEditingController(text:''); @override void dispose(){host.dispose();port.dispose();super.dispose();} @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('اتصال يدوي')),body:ListView(padding:const EdgeInsets.all(20),children:[TextField(controller:host,decoration:const InputDecoration(labelText:'IP الجهاز',hintText:'192.168.1.20')),const SizedBox(height:12),TextField(controller:port,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المنفذ',hintText:'مثال: 45455')),const SizedBox(height:18),FilledButton.icon(onPressed:(){final p=int.tryParse(port.text);if(host.text.trim().isEmpty||p==null)return;Navigator.push(context,MaterialPageRoute(builder:(_)=>ManualSendPage(storage:widget.storage,discovery:widget.discovery,target:NearbyDevice(id:'manual',name:'جهاز يدوي',host:host.text.trim(),port:p))));},icon:const Icon(Icons.link),label:const Text('متابعة'))])); }

class ManualSendPage extends StatelessWidget { const ManualSendPage({super.key,required this.storage,required this.discovery,required this.target}); final StorageService storage; final DiscoveryService discovery; final NearbyDevice target; @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('إرسال إلى جهاز')),body:Center(child:FilledButton.icon(onPressed:()async{final r=await FilePicker.platform.pickFiles(allowMultiple:true);if(r==null)return;final fs=r.files.where((e)=>e.path!=null).map((e)=>TransferFile(name:e.name,path:e.path!,size:File(e.path!).lengthSync())).toList();if(fs.isEmpty)return;Navigator.push(context,MaterialPageRoute(builder:(_)=>SendPage(storage:storage,discovery:discovery,files:fs,target:target)));},icon:const Icon(Icons.folder_open),label:const Text('اختيار الملفات')))); }

class HistoryPage extends StatefulWidget { const HistoryPage({super.key,required this.storage}); final StorageService storage; @override State<HistoryPage> createState()=>_HistoryPageState(); }
class _HistoryPageState extends State<HistoryPage>{List<TransferRecord> records=[];@override void initState(){super.initState();_load();}Future<void>_load()async{records=await widget.storage.history();if(mounted)setState((){});} @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('سجل النقل'),actions:[IconButton(onPressed:()async{await widget.storage.clearHistory();_load();},icon:const Icon(Icons.delete_outline))]),body:records.isEmpty?const Center(child:Text('لا يوجد سجل بعد.')):ListView.builder(padding:const EdgeInsets.all(14),itemCount:records.length,itemBuilder:(c,i){final r=records[i];return Card(child:ListTile(leading:Icon(r.direction==TransferDirection.sent?Icons.upload_rounded:Icons.download_rounded),title:Text(r.device,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${formatBytes(r.completedBytes)} • ${r.status}\n${r.createdAt.toLocal()}'),isThreeLine:true));})); }

class SettingsPage extends StatefulWidget { const SettingsPage({super.key,required this.storage}); final StorageService storage; @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage>{final c=TextEditingController();@override void initState(){super.initState();widget.storage.deviceName().then((v){if(mounted)c.text=v;});}@override void dispose(){c.dispose();super.dispose();}@override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('الإعدادات')),body:ListView(padding:const EdgeInsets.all(20),children:[TextField(controller:c,decoration:const InputDecoration(labelText:'اسم الجهاز')),const SizedBox(height:14),FilledButton(onPressed:()async{await widget.storage.setDeviceName(c.text);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ اسم الجهاز')));},child:const Text('حفظ')),const SizedBox(height:20),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('الأمان: كل جلسة تتطلب موافقة المستلم، ويظهر رمز تحقق للجلسة. النقل يتم مباشرة داخل الشبكة المحلية.')))]));}

Future<bool> confirm(BuildContext context,String title,String message) async => await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(message),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رفض')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('قبول'))]))??false;
