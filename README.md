#  Flutter Download Manager

[![pub package](https://img.shields.io/pub/v/flutter_download_manager.svg)](https://pub.dev/packages/flutter_download_manager)
[![likes](https://img.shields.io/pub/likes/flutter_download_manager)](https://pub.dev/packages/flutter_download_manager/score)
[![popularity](https://img.shields.io/pub/popularity/flutter_download_manager)](https://pub.dev/packages/flutter_download_manager/score)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A powerful, resumable, and queue-based download manager for Flutter — built for production apps.

---

##  Highlights

*  Parallel downloads with queue system
*  Resume & pause downloads
*  Smart retry mechanism
*  Real-time progress & speed tracking
*  Save directly to Downloads (Android MediaStore)
*  iOS support (Documents directory)
*  Built-in notifications
*  Batch downloads
*  Persistent tasks (auto restore)
*  Open file automatically after download

---



##  Installation

```yaml
dependencies:
  flutter_download_manager: latest
```

---

##  Quick Start

### Initialize

```dart
await DownloadNotificationService.init();
await DownloadNotificationService.requestPermission();
```

---

### Create Controller

```dart
final controller = DownloadController(
  maxConcurrent: 2,
);
```

---

### Download a File

```dart
final task = controller.addTask(
  'https://example.com/file.pdf',
  subFolder: 'MyApp',
  openAfterDownload: true,
);

await controller.startTask(task);
```

---

##  Usage Examples

###  Download PDF

```dart
controller.addTask(
  'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  openAfterDownload: true,
);
```

---

###  Download Image

```dart
controller.addTask(
  'https://www.w3.org/Icons/w3c_home.png',
);
```

---

###  Batch Download

```dart
controller.addBatch([
  'https://example.com/file1.pdf',
  'https://example.com/file2.png',
]);
```

---

###  Pause / Resume

```dart
controller.pauseTask(task);
controller.resumeTask(task);
```

---

###  Cancel

```dart
await controller.cancelTask(task);
```

---

##  Open File After Download

Automatically open files when completed:

```dart
controller.addTask(
  url,
  openAfterDownload: true,
);
```

---

##  File Storage

### Android

* Uses **MediaStore API**
* Saves to **Downloads/**
* No storage permission required

### iOS

* Saves to **Application Documents Directory**

---

##  Listen to Progress

```dart
controller.onTaskUpdated.listen((task) {
  print(task.progress);
});
```

---

##  Configuration

| Option            | Description                  |
| ----------------- | ---------------------------- |
| maxConcurrent     | Number of parallel downloads |
| priority          | Download priority            |
| headers           | Custom request headers       |
| retryDelay        | Delay between retries        |
| maxRetries        | Retry attempts               |
| subFolder         | Save inside subfolder        |
| openAfterDownload | Auto open file               |

---

##  How It Works

* Uses **Dio** for downloading
* Supports **HTTP Range requests** (resume)
* Stores tasks using **SharedPreferences**
* Uses **MethodChannel** for Android file saving

---

## ⚠️ Notes

* Resume requires server support for `Range` headers
* Some file types require external apps to open
* Android 13+ requires notification permission

---
---


