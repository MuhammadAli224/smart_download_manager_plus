import 'package:flutter/material.dart';
import 'package:flutter_download_manager/flutter_download_manager.dart';
import 'package:open_filex/open_filex.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DownloadNotificationService.init(
    channelName: 'My App Downloads',
    progressColor: const Color(0xFF1565C0),
    ledColor: const Color(0xFF1565C0),
  );

  await DownloadNotificationService.requestPermission();

  runApp(const MyApp());
}

const _samples = [
  {
    'label': 'PDF',
    'url':
        'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  },
  {'label': 'Image', 'url': 'https://www.w3.org/Icons/w3c_home.png'},
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
      ),
      home: const DownloadScreen(),
    );
  }
}

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  late final DownloadController controller;

  @override
  void initState() {
    super.initState();

    controller = DownloadController(
      maxConcurrent: 2,
      onTaskCompleted: (t) => _snack('✓ ${t.fileName} completed'),
      onTaskFailed: (t) => _snack('✗ ${t.fileName} failed'),
      onTaskPaused: (t) => _snack('⏸ ${t.fileName} paused'),
      onTaskProgress: (_) => setState(() {}),
    );

    controller.restoreTasks().then((_) => setState(() {}));
    controller.onTaskUpdated.listen((_) => setState(() {}));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void refresh() => setState(() {});

  // 📊 DASHBOARD
  Widget _stats() {
    final active = controller.tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .length;

    final queued = controller.tasks
        .where((t) => t.status == DownloadStatus.idle)
        .length;

    final done = controller.tasks
        .where((t) => t.status == DownloadStatus.completed)
        .length;

    final speed = controller.tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .fold<double>(0, (sum, t) => sum + t.speed);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Active', active, Icons.downloading),
          _stat('Queued', queued, Icons.schedule),
          _stat('Done', done, Icons.check_circle),
          _stat('Speed', FileHelper.formatSpeed(speed), Icons.speed),
        ],
      ),
    );
  }

  Widget _stat(String label, dynamic value, IconData icon) {
    return Column(
      children: [
        Icon(icon),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _addTask(String url) {
    controller.addTask(
      url,
      subFolder: 'MyApp',
      maxRetries: 2,
      headers: {'Accept': '*/*'},
      priority: 1,
      openAfterDownload: true,
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () => controller.startAll(onUpdate: refresh),
          ),
          IconButton(
            icon: const Icon(Icons.pause),
            onPressed: () => controller.pauseAll(onUpdate: refresh),
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: () => controller.cancelAll(onUpdate: refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _stats(),

          // Quick Add
          Wrap(
            spacing: 8,
            children: [
              ..._samples.map(
                (f) => ActionChip(
                  label: Text(f['label']!),
                  onPressed: () => _addTask(f['url']!),
                ),
              ),
              ActionChip(
                label: const Text('Batch'),
                onPressed: () {
                  controller.addBatch(
                    _samples.map((e) => e['url']!).toList(),
                    subFolder: 'Batch',
                  );
                  refresh();
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          Expanded(
            child: controller.tasks.isEmpty
                ? const Center(child: Text('No downloads yet'))
                : ListView.builder(
                    itemCount: controller.tasks.length,
                    itemBuilder: (_, i) {
                      final t = controller.tasks[i];

                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: ListTile(
                          title: Text(t.fileName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(value: t.progress),
                              Text(
                                '${(t.progress * 100).toStringAsFixed(1)}% • ${FileHelper.formatSpeed(t.speed)}',
                              ),
                              if (t.savedPath != null)
                                Text(
                                  t.savedPath!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: _actions(t),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _actions(DownloadTask t) {
    switch (t.status) {
      case DownloadStatus.idle:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () => controller.startTask(t, onUpdate: refresh),
        );

      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () => controller.pauseTask(t, onUpdate: refresh),
        );

      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () => controller.resumeTask(t, onUpdate: refresh),
        );

      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () {
            if (t.savedPath != null) {
              OpenFilex.open(t.savedPath!);
            }
          },
        );

      case DownloadStatus.error:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => controller.startTask(t, onUpdate: refresh),
        );
    }
  }
}
