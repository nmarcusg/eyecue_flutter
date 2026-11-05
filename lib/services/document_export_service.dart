import 'dart:io';

import 'package:flutter/services.dart';

/// Saves a staged export through Android's user-selected document provider.
/// Null means the picker was cancelled; completion means the provider stream
/// was written and closed. The native side never receives session/token data
/// through a large platform-channel payload, only the private staging path.
class DocumentExportService {
  const DocumentExportService();

  static const _channel = MethodChannel('eyecue/document_export');

  Future<String?> save({required File source, required String mimeType}) =>
      _channel.invokeMethod<String>('saveDocument', {
        'sourcePath': source.path,
        'fileName': source.uri.pathSegments.last,
        'mimeType': mimeType,
      });
}
