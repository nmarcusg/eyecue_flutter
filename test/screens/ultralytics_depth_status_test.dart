import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/monocular_depth_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled wins when depth estimation is off', () {
    expect(
      depthStatusFor(
        mdeEnabled: false,
        state: DepthRunState.ready,
        accelerator: 'gpu',
      ),
      'disabled',
    );
    expect(
      depthStatusFor(
        mdeEnabled: false,
        state: DepthRunState.degraded,
        accelerator: null,
      ),
      'disabled',
    );
  });

  test('degraded and loading come from the model state', () {
    expect(
      depthStatusFor(
        mdeEnabled: true,
        state: DepthRunState.degraded,
        accelerator: 'gpu',
      ),
      'degraded',
    );
    expect(
      depthStatusFor(
        mdeEnabled: true,
        state: DepthRunState.loading,
        accelerator: null,
      ),
      'loading',
    );
    // Idle with no loaded model instance has no known accelerator yet.
    expect(
      depthStatusFor(
        mdeEnabled: true,
        state: DepthRunState.idle,
        accelerator: null,
      ),
      'loading',
    );
  });

  test('a loaded model reports its accelerator', () {
    expect(
      depthStatusFor(
        mdeEnabled: true,
        state: DepthRunState.ready,
        accelerator: 'gpu',
      ),
      'gpu',
    );
    expect(
      depthStatusFor(
        mdeEnabled: true,
        state: DepthRunState.ready,
        accelerator: 'cpu',
      ),
      'cpu',
    );
  });
}
