import 'package:eyecue_flutter/models/model_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveDepthAccelerator', () {
    test('maps the three documented values', () {
      expect(resolveDepthAccelerator('auto'), DepthAccelerator.auto);
      expect(resolveDepthAccelerator('cpu'), DepthAccelerator.cpu);
      expect(resolveDepthAccelerator('gpu'), DepthAccelerator.gpu);
    });

    test('tolerates case and surrounding whitespace', () {
      expect(resolveDepthAccelerator('CPU'), DepthAccelerator.cpu);
      expect(resolveDepthAccelerator('  Gpu  '), DepthAccelerator.gpu);
      expect(resolveDepthAccelerator('Auto'), DepthAccelerator.auto);
    });

    test('an unknown or empty value falls back to auto', () {
      for (final raw in ['', '   ', 'npu', 'gpu1', 'cuda', 'fastest']) {
        expect(
          resolveDepthAccelerator(raw),
          DepthAccelerator.auto,
          reason: 'a build-flag typo must not disable the GPU path',
        );
      }
    });

    test('only the cpu policy asks for the CPU delegate', () {
      expect(DepthAccelerator.auto.useGpu, isTrue);
      expect(DepthAccelerator.gpu.useGpu, isTrue);
      expect(DepthAccelerator.cpu.useGpu, isFalse);
    });
  });
}
