import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import 'telemetry_export_service.dart';
import 'telemetry_service.dart';

/// Build-time configuration for the researcher telemetry ingestion endpoint.
///
/// These values are deliberately supplied with `--dart-define`; no project
/// URL, key, or study configuration is committed to the application source.
class TelemetryUploadConfiguration {
  const TelemetryUploadConfiguration({
    required this.ingestUrl,
    required this.publishableKey,
  });

  const TelemetryUploadConfiguration.fromEnvironment()
    : ingestUrl = const String.fromEnvironment('EYECUE_TELEMETRY_INGEST_URL'),
      publishableKey = const String.fromEnvironment(
        'EYECUE_SUPABASE_PUBLISHABLE_KEY',
      );

  final String ingestUrl;
  final String publishableKey;

  bool get isConfigured =>
      Uri.tryParse(ingestUrl)?.hasScheme == true && publishableKey.isNotEmpty;
}

/// Research context supplied by a researcher for one explicitly uploaded
/// session. It deliberately has no free-text field to avoid accidental PII.
class ResearchSessionMetadata {
  const ResearchSessionMetadata({
    required this.participantCode,
    required this.studyScenario,
  });

  final String participantCode;
  final String studyScenario;

  bool get isValid =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(participantCode) &&
      studyScenario.trim().isNotEmpty &&
      studyScenario.trim().length <= 80;

  Map<String, dynamic> toJson() => {
    'participantCode': participantCode.trim(),
    'studyScenario': studyScenario.trim(),
  };
}

class TelemetryUploadResult {
  const TelemetryUploadResult._({this.errorMessage});

  const TelemetryUploadResult.success() : this._();

  const TelemetryUploadResult.failure(String message)
    : this._(errorMessage: message);

  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

class TelemetryUploadRequest {
  const TelemetryUploadRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class TelemetryUploadResponse {
  const TelemetryUploadResponse(this.statusCode);

  final int statusCode;
}

typedef TelemetryUploadSender =
    Future<TelemetryUploadResponse> Function(TelemetryUploadRequest request);

/// Sends a consented, image-free telemetry snapshot to the researcher API.
///
/// Upload is never automatic: callers must collect one manual confirmation for
/// the current session before invoking this service. Failed uploads remain
/// recoverable through the unchanged JSON/CSV export controls.
class TelemetryUploadService {
  TelemetryUploadService({
    TelemetryUploadConfiguration? configuration,
    TelemetryExportService? exportService,
    TelemetryUploadSender? sender,
    DateTime Function()? clock,
    this.maxBodyBytes = maxUploadBodyBytes,
  }) : _configuration =
           configuration ??
           const TelemetryUploadConfiguration.fromEnvironment(),
       _exportService = exportService ?? TelemetryExportService(),
       _sender = sender ?? _send,
       _clock = clock ?? DateTime.now;

  /// The ingest function's own body limit. A larger body is refused locally so
  /// the server's `413` is never the first signal a session was lost.
  static const int maxUploadBodyBytes = 2000000;

  final TelemetryUploadConfiguration _configuration;
  final TelemetryExportService _exportService;
  final TelemetryUploadSender _sender;
  final DateTime Function() _clock;

  /// Effective body limit; a test may lower it to drive the refusal branch.
  ///
  /// The annotation only documents that tests are the intended caller: it does
  /// not prevent application code from passing a wider value through the named
  /// constructor parameter. Nothing here enforces the 2 000 000 bound on a
  /// caller that widens it, so keeping the default is a convention, not a
  /// guarantee.
  @visibleForTesting
  final int maxBodyBytes;

  bool get isConfigured => _configuration.isConfigured;

  Future<TelemetryUploadResult> upload({
    required TelemetryService telemetry,
    required ResearchSessionMetadata metadata,
    AppSettings? settings,
  }) async {
    if (!isConfigured) {
      return const TelemetryUploadResult.failure(
        'Research upload has not been configured for this build.',
      );
    }
    if (!metadata.isValid) {
      return const TelemetryUploadResult.failure(
        'Enter a valid participant code and study scenario.',
      );
    }

    final uri = Uri.tryParse(_configuration.ingestUrl);
    if (uri == null) {
      return const TelemetryUploadResult.failure(
        'Research upload address is invalid.',
      );
    }

    final payload = {
      'ingestionSchemaVersion': 1,
      'submittedAt': _clock().toUtc().toIso8601String(),
      'consent': {'manualSessionUpload': true},
      'study': metadata.toJson(),
      'telemetry': _exportService
          .snapshot(telemetry: telemetry, settings: settings)
          .toJson(),
    };

    final body = jsonEncode(payload);
    // Never truncate: a shortened payload would be silently wrong research
    // data, so an oversized session is reported and the local export kept.
    if (utf8.encode(body).length > maxBodyBytes) {
      return const TelemetryUploadResult.failure(
        'This session is too large to upload. Save a local export to keep the data.',
      );
    }

    try {
      final response = await _sender(
        TelemetryUploadRequest(
          uri: uri,
          headers: {
            HttpHeaders.authorizationHeader:
                'Bearer ${_configuration.publishableKey}',
            'apikey': _configuration.publishableKey,
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: body,
        ),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const TelemetryUploadResult.success();
      }
      return const TelemetryUploadResult.failure(
        'The research server could not accept this session. Save an offline export and try again later.',
      );
    } on TimeoutException {
      return const TelemetryUploadResult.failure(
        'The upload timed out. Save an offline export and try again later.',
      );
    } on SocketException {
      return const TelemetryUploadResult.failure(
        'No network connection is available. Save an offline export and try again later.',
      );
    } on HttpException {
      return const TelemetryUploadResult.failure(
        'The research server could not be reached. Save an offline export and try again later.',
      );
    } catch (_) {
      return const TelemetryUploadResult.failure(
        'The session could not be uploaded. Save an offline export and try again later.',
      );
    }
  }

  static Future<TelemetryUploadResponse> _send(
    TelemetryUploadRequest request,
  ) async {
    final client = HttpClient();
    try {
      final requestHandle = await client
          .postUrl(request.uri)
          .timeout(const Duration(seconds: 15));
      request.headers.forEach(requestHandle.headers.set);
      requestHandle.write(request.body);
      final response = await requestHandle.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>();
      return TelemetryUploadResponse(response.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}
