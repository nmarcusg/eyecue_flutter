import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/detector_model_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled graph is the only fixture with a real TFLite flatbuffer.
const String _assetPath = 'assets/yolov8n_int8_new_metadata.tflite';
const int _cocoClassCount = 80;

class _FakePicker implements ModelFilePicker {
  _FakePicker(this.path);

  final String? path;

  @override
  Future<String?> pickTflite() async => path;
}

void main() {
  late Directory tempDir;
  late SettingsService settings;
  late Uint8List modelBytes;
  late String modelFingerprint;

  setUpAll(() {
    modelBytes = File(_assetPath).readAsBytesSync();
    modelFingerprint = tfliteFingerprint(modelBytes);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('eyecue_settings_model');
    settings = SettingsService(store: InMemorySettingsStore());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<String> cocoLabels() =>
      List<String>.generate(_cocoClassCount, (index) => 'class$index');

  DetectorModelService buildService({String? pickPath}) => DetectorModelService(
    settings,
    picker: _FakePicker(pickPath),
    builtInLabelsLoader: () async => cocoLabels(),
    inspect: (path) async => {'task': 'detect', 'labels': cocoLabels()},
    modelsDirectory: () async => Directory('${tempDir.path}/eyecue_models'),
    // The chunked re-hash of a 12 MB copy is covered by the service's own
    // tests; here it would need hundreds of real-async pump cycles.
    fingerprintReader: (file) async => modelFingerprint,
  );

  String writeSource() => (File(
    '${tempDir.path}/source.tflite',
  )..writeAsBytesSync(modelBytes)).path;

  /// Real file I/O never completes inside the fake-async test zone, so the
  /// widget is pumped while the real event loop (from [WidgetTester.runAsync])
  /// finishes the service call.
  Future<void> driveIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (done()) return;
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    DetectorModelService service,
  ) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: settings,
          detectorModel: service,
          onOpenLogsReports: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the built-in model from the service', (tester) async {
    late DetectorModelService service;
    await tester.runAsync(() async {
      await settings.load();
      service = buildService();
      await service.load();
    });

    await pumpSettings(tester, service);

    expect(find.text('Detector Model'), findsOneWidget);
    expect(find.text('Built-in YOLOv8n · 80 classes'), findsOneWidget);
    expect(find.text('Built-in detector'), findsOneWidget);
  });

  testWidgets('renders a selected custom model from the service', (
    tester,
  ) async {
    late DetectorModelService service;
    late ModelImportResult imported;
    await tester.runAsync(() async {
      await settings.load();
      service = buildService();
      await service.load();
      imported = await service.importFromPath(
        writeSource(),
        displayName: 'Obstacle Detector v2',
      );
    });
    expect(imported.ok, isTrue);

    await pumpSettings(tester, service);

    expect(find.text('Obstacle Detector v2 · 80 classes'), findsOneWidget);
    expect(find.text('Imported model'), findsOneWidget);
  });

  testWidgets('an import failure surfaces the message and keeps the card', (
    tester,
  ) async {
    final empty = File('${tempDir.path}/empty.tflite')
      ..writeAsBytesSync(const <int>[]);
    late DetectorModelService service;
    await tester.runAsync(() async {
      await settings.load();
      service = buildService(pickPath: empty.path);
      await service.load();
    });

    await pumpSettings(tester, service);

    await tester.tap(find.text('Choose model file…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Broken Model');
    await tester.tap(find.text('Import'));
    await driveIo(
      tester,
      () => find.textContaining('That file is empty').evaluate().isNotEmpty,
    );

    expect(find.textContaining('That file is empty'), findsOneWidget);
    expect(find.text('Built-in YOLOv8n · 80 classes'), findsOneWidget);
  });

  testWidgets('a cancelled pick leaves the card unchanged', (tester) async {
    late DetectorModelService service;
    await tester.runAsync(() async {
      await settings.load();
      service = buildService();
      await service.load();
    });

    await pumpSettings(tester, service);

    await tester.tap(find.text('Choose model file…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unused Name');
    await tester.tap(find.text('Import'));
    await driveIo(tester, () => find.text('Import').evaluate().isEmpty);

    expect(find.textContaining('could not be imported'), findsNothing);
    expect(find.text('Built-in YOLOv8n · 80 classes'), findsOneWidget);
  });

  testWidgets('switching to built-in keeps the import and restores it', (
    tester,
  ) async {
    late DetectorModelService service;
    late List<String> stored;
    await tester.runAsync(() async {
      await settings.load();
      service = buildService();
      await service.load();
      final imported = await service.importFromPath(
        writeSource(),
        displayName: 'Obstacle Detector v2',
      );
      expect(imported.ok, isTrue);
      stored = await service.debugStoredFiles();
    });

    await pumpSettings(tester, service);

    await tester.tap(find.text('Use built-in detector'));
    await tester.pumpAndSettle();
    expect(find.text('Built-in YOLOv8n · 80 classes'), findsOneWidget);
    late List<String> afterSwitch;
    await tester.runAsync(() async {
      afterSwitch = await service.debugStoredFiles();
    });
    expect(afterSwitch, stored);

    await tester.tap(find.text('Use imported model'));
    await driveIo(tester, () => service.isCustomSelected);
    expect(find.text('Obstacle Detector v2 · 80 classes'), findsOneWidget);
  });

  testWidgets('the recovery message is rendered as a warning', (tester) async {
    late DetectorModelService reloaded;
    await tester.runAsync(() async {
      await settings.load();
      final first = buildService();
      await first.load();
      final imported = await first.importFromPath(
        writeSource(),
        displayName: 'Obstacle Detector v2',
      );
      expect(imported.ok, isTrue);

      // The stored copy disappears between sessions, so the restored selection
      // is the built-in one with a visible recovery message.
      Directory('${tempDir.path}/eyecue_models').deleteSync(recursive: true);
      reloaded = buildService();
      await reloaded.load();
    });
    expect(reloaded.selectionRecoveryMessage, isNotNull);

    await pumpSettings(tester, reloaded);

    expect(find.text(reloaded.selectionRecoveryMessage!), findsOneWidget);
    expect(find.text('Built-in YOLOv8n · 80 classes'), findsOneWidget);
  });
}
