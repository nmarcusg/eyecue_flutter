import 'dart:io';

import 'package:eyecue_flutter/services/document_export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eyecue/document_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Save as passes a file reference and preserves the selected filename',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return 'renamed-trial.json';
      });
      final name = await const DocumentExportService().save(
        source: File('/cache/trial.json'),
        mimeType: 'application/json',
      );
      expect(name, 'renamed-trial.json');
      expect(received!.method, 'saveDocument');
      expect(received!.arguments, {
        'sourcePath': '/cache/trial.json',
        'fileName': 'trial.json',
        'mimeType': 'application/json',
      });
    },
  );

  test('picker cancellation remains distinct from success', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await const DocumentExportService().save(
        source: File('/cache/trial.csv'),
        mimeType: 'text/csv',
      ),
      isNull,
    );
  });

  test(
    'destination write failure is propagated rather than reported saved',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'write_failed');
      });
      await expectLater(
        const DocumentExportService().save(
          source: File('/cache/trial.json'),
          mimeType: 'application/json',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
