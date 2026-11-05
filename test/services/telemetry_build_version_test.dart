import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export carries the build identity provided by the build pipeline', () {
    const expected = String.fromEnvironment(
      'EYECUE_APP_VERSION',
      defaultValue: '1.0.0+1',
    );
    final telemetry = TelemetryService();
    addTearDown(telemetry.dispose);
    final json = TelemetryExportService()
        .snapshot(telemetry: telemetry)
        .toJson();
    expect(json['appVersion'], expected);
  });

  test('recorded identity is not replaced by the current build identity', () {
    final previous = TelemetryService(appVersion: 'previous-recorded-version');
    addTearDown(previous.dispose);
    expect(
      TelemetryExportService().snapshot(telemetry: previous).appVersion,
      'previous-recorded-version',
    );
  });
}
