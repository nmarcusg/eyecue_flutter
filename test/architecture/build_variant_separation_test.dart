import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release variants separate permissions and Dart entrypoints', () {
    final publicManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final studyManifest = File(
      'android/app/src/study/AndroidManifest.xml',
    ).readAsStringSync();
    expect(publicManifest, isNot(contains('android.permission.INTERNET')));
    expect(studyManifest, contains('android.permission.INTERNET'));

    final publicMain = File('lib/main.dart').readAsStringSync();
    for (final forbidden in [
      'ResearchSessionService',
      'TelemetryUploadService',
      'TelemetryExportService',
      'DocumentExportService',
      'logs_reports_screen',
    ]) {
      expect(publicMain, isNot(contains(forbidden)), reason: forbidden);
    }

    final studyMain = File('lib/main_study.dart').readAsStringSync();
    expect(studyMain, contains('ResearchSessionService'));
    expect(studyMain, contains('logs_reports_screen.dart'));
    expect(studyMain, contains('LogsReportsScreen'));

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('flavorDimensions'));
    expect(gradle, contains('app.eyecue.mobile'));
    expect(gradle, contains('app.eyecue.mobile.study'));
    expect(gradle, contains('hasUploadSigning'));
    expect(gradle, isNot(contains('eyecueStudyBuild')));
    expect(gradle, isNot(contains('EYECUE_STUDY_BUILD')));

    final workflow = File(
      '.github/workflows/android-build.yml',
    ).readAsStringSync();
    expect(workflow, contains('--flavor public'));
    expect(workflow, contains('--flavor study -t lib/main_study.dart'));
    for (final line in workflow.split('\n')) {
      if (line.contains('--flavor public')) {
        expect(line, isNot(contains('EYECUE_TELEMETRY_INGEST_URL')));
      }
    }
  });
}
