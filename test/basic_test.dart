import 'package:flutter_test/flutter_test.dart';
import 'package:smart_download_manager_plus/smart_download_manager_plus.dart';

void main() {
  test('DownloadTask creation', () {
    final task = DownloadTask(
      id: '1',
      url: 'https://example.com/file.pdf',
      fileName: 'file.pdf',
    );

    expect(task.fileName, 'file.pdf');
    expect(task.progress, 0);
  });
}