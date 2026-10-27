import 'dart:async';
import 'dart:io';

import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTtsEngine implements TtsEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> recover() async {}
  @override
  Future<int> speak(String text) async => 1;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('model path resolution alone does not publish ready', (
    tester,
  ) async {
    final states = <DetectionRuntimeState>[];
    final failures = <String>[];
    final viewIds = <String>[];
    var failInspection = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        if (call.method == 'checkPermissionStatus') return 1;
        if (call.method == 'requestPermissions') return <int, int>{1: 1};
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (call) async => <Object?>[],
    );
    final documents = Directory.systemTemp.createTempSync('eyecue-readiness');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => documents.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yolo_single_image_channel'),
      (call) async {
        if (failInspection) throw PlatformException(code: 'inspection-failed');
        return <String, dynamic>{'task': 'detect'};
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter/platform_views'),
      (call) async {
        if (call.method == 'resize') {
          final args = call.arguments as Map;
          return <String, Object>{
            'width': args['width'] as double,
            'height': args['height'] as double,
          };
        }
        if (call.method != 'create') return null;
        final args = call.arguments as Map;
        final params = args['params'];
        Object? decoded;
        if (params is ByteData) {
          decoded = const StandardMessageCodec().decodeMessage(params);
        } else if (params is Uint8List) {
          decoded = const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(params),
          );
        } else if (params is List<int>) {
          decoded = const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(Uint8List.fromList(params)),
          );
        }
        if (decoded is Map && decoded['viewId'] is String) {
          final viewId = decoded['viewId'] as String;
          viewIds.add(viewId);
          messenger.setMockMethodCallHandler(
            MethodChannel('com.ultralytics.yolo/controlChannel_$viewId'),
            (call) async => null,
          );
        }
        return 0;
      },
    );
    addTearDown(() {
      documents.deleteSync(recursive: true);
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('yolo_single_image_channel'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform_views'),
        null,
      );
    });

    final settings = SettingsService(store: InMemorySettingsStore());
    final tts = TtsService(engine: _FakeTtsEngine());
    final stopTeardown = Completer<void>();
    var holdStopTeardown = false;
    await tts.init();
    addTearDown(tts.dispose);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: UltralyticsDetectionScreen(
          settings: settings,
          tts: tts,
          telemetry: TelemetryService(),
          haptics: HapticsService(
            light: () async {},
            medium: () async {},
            heavy: () async {},
          ),
          coordinator: EngineCoordinator(),
          onRuntimeStateChanged: (state, _) => states.add(state),
          onFailure: (failure, _) => failures.add(failure.category.name),
          readinessTimeout: const Duration(seconds: 2),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Start Detection'));
    await tester.pump();
    for (var i = 0; i < 40 && viewIds.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(viewIds, hasLength(1));
    expect(states, contains(DetectionRuntimeState.loadingModel));
    expect(states, isNot(contains(DetectionRuntimeState.ready)));
    final payload = <String, dynamic>{
      'detections': <dynamic>[],
      'fps': 12.0,
      'processingTimeMs': 25.0,
      'timestamp': 1,
      'frameNumber': 1,
      'imageWidth': 640,
      'imageHeight': 480,
    };
    Future<void> toggleWithTwoFingerDoubleTap() async {
      final center = tester.getCenter(find.byType(GestureSurface));
      Future<void> twoFingerTap() async {
        final first = await tester.startGesture(center);
        final second = await tester.startGesture(center + const Offset(0, 40));
        await first.up();
        await second.up();
        await tester.pump(const Duration(milliseconds: 16));
      }

      await twoFingerTap();
      await twoFingerTap();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.tap(find.byType(GestureSurface));
    await tester.pump(const Duration(milliseconds: 400));
    expect(states.last, DetectionRuntimeState.paused);
    await tester.tap(find.byType(GestureSurface));
    await tester.pump(const Duration(milliseconds: 400));
    expect(states.last, DetectionRuntimeState.loadingModel);
    expect(states, isNot(contains(DetectionRuntimeState.ready)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failures, [DetectionFailureCategory.modelLoading.name]);
    failures.clear();

    await tester.pumpWidget(const SizedBox.shrink());
    states.clear();
    final coordinator = EngineCoordinator();
    await tester.pumpWidget(
      MaterialApp(
        home: UltralyticsDetectionScreen(
          settings: settings,
          tts: tts,
          telemetry: TelemetryService(),
          haptics: HapticsService(
            light: () async {},
            medium: () async {
              if (holdStopTeardown) await stopTeardown.future;
            },
            heavy: () async {},
          ),
          coordinator: coordinator,
          onRuntimeStateChanged: (state, _) {
            states.add(state);
            coordinator.reportState(state);
          },
          readinessTimeout: const Duration(seconds: 5),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Start Detection'));
    await tester.pump();
    for (var i = 0; i < 40 && viewIds.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(viewIds, hasLength(2));
    expect(states.last, DetectionRuntimeState.loadingModel);
    final nonEmptyPayload = <String, dynamic>{
      ...payload,
      'detections': <dynamic>[
        <String, dynamic>{
          'classIndex': 0,
          'className': 'person',
          'confidence': 0.9,
          'boundingBox': <String, dynamic>{
            'left': 10.0,
            'top': 20.0,
            'right': 110.0,
            'bottom': 220.0,
          },
          'normalizedBox': <String, dynamic>{
            'left': 0.1,
            'top': 0.1,
            'right': 0.5,
            'bottom': 0.8,
          },
        },
      ],
    };
    holdStopTeardown = true;
    await toggleWithTwoFingerDoubleTap();
    expect(states.last, DetectionRuntimeState.loadingModel);
    await messenger.handlePlatformMessage(
      'com.ultralytics.yolo/detectionResults_${viewIds.last}',
      const StandardMethodCodec().encodeSuccessEnvelope(nonEmptyPayload),
      (ByteData? data) {},
    );
    await tester.pump();
    expect(states, isNot(contains(DetectionRuntimeState.ready)));
    expect(find.textContaining('person'), findsNothing);
    stopTeardown.complete();
    holdStopTeardown = false;
    await tester.pump();
    await tester.pump();
    expect(states.last, DetectionRuntimeState.stopped);

    await toggleWithTwoFingerDoubleTap();
    for (var i = 0; i < 40 && viewIds.length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(viewIds, hasLength(3));
    expect(states.last, DetectionRuntimeState.loadingModel);
    await messenger.handlePlatformMessage(
      'com.ultralytics.yolo/detectionResults_${viewIds.last}',
      const StandardMethodCodec().encodeSuccessEnvelope(nonEmptyPayload),
      (ByteData? data) {},
    );
    await tester.pump();
    expect(states.last, DetectionRuntimeState.ready);

    await messenger.handlePlatformMessage(
      'com.ultralytics.yolo/detectionResults_${viewIds[1]}',
      const StandardMethodCodec().encodeSuccessEnvelope(nonEmptyPayload),
      (ByteData? data) {},
    );
    await tester.pump();
    expect(states.last, DetectionRuntimeState.ready);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(GestureSurface));
    await tester.pump(const Duration(milliseconds: 400));
    expect(states.last, DetectionRuntimeState.paused);
    await tester.tap(find.byType(GestureSurface));
    await tester.pump(const Duration(milliseconds: 400));
    expect(states.last, DetectionRuntimeState.ready);

    await toggleWithTwoFingerDoubleTap();
    expect(states.last, DetectionRuntimeState.stopped);
    await messenger.handlePlatformMessage(
      'com.ultralytics.yolo/detectionResults_${viewIds.last}',
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (ByteData? data) {},
    );
    await tester.pump();
    expect(states.last, DetectionRuntimeState.stopped);
    await toggleWithTwoFingerDoubleTap();
    for (var i = 0; i < 40 && viewIds.length < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(viewIds, hasLength(4));
    expect(states.last, DetectionRuntimeState.loadingModel);
    await toggleWithTwoFingerDoubleTap();
    expect(states.last, DetectionRuntimeState.stopped);
    await tester.pump(const Duration(seconds: 6));
    expect(failures, isEmpty);
    await toggleWithTwoFingerDoubleTap();
    for (var i = 0; i < 40 && viewIds.length < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(viewIds, hasLength(5));
    expect(states.last, DetectionRuntimeState.loadingModel);
    await messenger.handlePlatformMessage(
      'com.ultralytics.yolo/detectionResults_${viewIds.last}',
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (ByteData? data) {},
    );
    await tester.pump();
    expect(states.last, DetectionRuntimeState.ready);
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox.shrink());
    states.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: UltralyticsDetectionScreen(
          settings: settings,
          tts: tts,
          telemetry: TelemetryService(),
          haptics: HapticsService(
            light: () async {},
            medium: () async {},
            heavy: () async {},
          ),
          coordinator: EngineCoordinator(),
          onRuntimeStateChanged: (state, _) => states.add(state),
          onFailure: (failure, _) => failures.add(failure.category.name),
          readinessTimeout: const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Start Detection'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failures, contains(DetectionFailureCategory.modelLoading.name));

    await tester.pumpWidget(const SizedBox.shrink());
    states.clear();
    final failureCount = failures.length;
    failInspection = true;
    await tester.pumpWidget(
      MaterialApp(
        home: UltralyticsDetectionScreen(
          settings: settings,
          tts: tts,
          telemetry: TelemetryService(),
          haptics: HapticsService(
            light: () async {},
            medium: () async {},
            heavy: () async {},
          ),
          coordinator: EngineCoordinator(),
          onRuntimeStateChanged: (state, _) => states.add(state),
          onFailure: (failure, _) => failures.add(failure.category.name),
          readinessTimeout: const Duration(seconds: 5),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Start Detection'));
    for (var i = 0; i < 40 && failures.length == failureCount; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failures.length, greaterThan(failureCount));
    expect(states, isNot(contains(DetectionRuntimeState.ready)));

    expect(tester.takeException(), isNull);
  });
}
