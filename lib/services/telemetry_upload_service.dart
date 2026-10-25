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
  const TelemetryUploadResult._({this.errorMessage, this.message});

  const TelemetryUploadResult.success() : this._();

  /// The server already stored this `(participant_code, client_session_id)`
  /// pair, so nothing was written this time.
  ///
  /// Success-like — the session is in the database — but deliberately distinct
  /// from [success]: the button re-arms after every attempt, so a second upload
  /// of a grown session is discarded by the idempotency key. Reporting that as
  /// the plain success text would hide lost data.
  const TelemetryUploadResult.alreadyUploaded()
    : this._(message: duplicateMessage);

  const TelemetryUploadResult.failure(String message)
    : this._(errorMessage: message);

  static const String duplicateMessage =
      'This session was already uploaded earlier and was not stored again. '
      'Save a local export if you have recorded more data since.';

  final String? errorMessage;

  /// Non-null only for [alreadyUploaded]: what to show instead of the plain
  /// success text.
  final String? message;

  bool get isSuccess => errorMessage == null;

  bool get isAlreadyUploaded => message != null;
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
  const TelemetryUploadResponse(this.statusCode, [this.body]);

  final int statusCode;

  /// Raw response body, when the sender kept it.
  ///
  /// Read only for the machine-readable `error` code (`400` answers carry
  /// `unsupported_schema_version`); it is never shown to the user verbatim.
  final String? body;
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

  /// Local refusal text; reused when the server answers `413` itself.
  static const String _tooLargeMessage =
      'This session is too large to upload. Save a local export to keep the data.';

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
      return const TelemetryUploadResult.failure(_tooLargeMessage);
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
        // `200 {duplicated: true}` is the replay answer: a row for this session
        // id already exists, so nothing was written. That is not the same thing
        // as this snapshot being stored, and must not say so.
        return _reportsDuplicate(response.body)
            ? const TelemetryUploadResult.alreadyUploaded()
            : const TelemetryUploadResult.success();
      }
      return _mapFailure(response);
    } on TimeoutException {
      return const TelemetryUploadResult.failure(
        'The upload timed out. Save a local export and try again later.',
      );
    } on SocketException {
      return const TelemetryUploadResult.failure(
        'No network connection is available. Save a local export and try again later.',
      );
    } on HttpException {
      return const TelemetryUploadResult.failure(
        'The research server could not be reached. Save a local export and try again later.',
      );
    } catch (_) {
      return const TelemetryUploadResult.failure(
        'The session could not be uploaded. Save a local export and try again later.',
      );
    }
  }

  /// True when a 2xx body reports `{"duplicated": true}`.
  static bool _reportsDuplicate(String? body) {
    if (body == null || body.isEmpty) return false;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['duplicated'] == true;
    } on FormatException {
      // The 4 KiB read cap can cut the body mid-JSON, and a replay must still
      // not be reported as a write: read the flag out of the surviving prefix.
      // shortcut: this is a prefix heuristic on an untrusted, possibly truncated
      // body — a cut before the flag reads as a write and the token anywhere in
      // a non-JSON body reads as a duplicate; switch to a length-delimited or
      // header-based signal if the ingest response contract changes.
      return body.replaceAll(RegExp(r'\s'), '').contains('"duplicated":true');
    }
  }

  /// Turns a non-2xx answer into one distinct, actionable message.
  ///
  /// The local session is untouched on every branch, so the JSON/CSV export
  /// still recovers it.
  static TelemetryUploadResult _mapFailure(TelemetryUploadResponse response) {
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      return const TelemetryUploadResult.failure(
        'This build is not authorised for the research upload. Save a local export and try again later.',
      );
    }
    if (status == 400) {
      if (_mentionsUnsupportedSchema(response.body)) {
        return const TelemetryUploadResult.failure(
          'This app build uses a telemetry format the research server does not accept. Update the app, or save a local export.',
        );
      }
      // A payload-shape defect is deterministic: sending the same session again
      // cannot change the answer, so no "try again later" here.
      return const TelemetryUploadResult.failure(
        'The research server rejected this session as invalid. Save a local export; sending it again will not help.',
      );
    }
    if (status == 413) {
      return const TelemetryUploadResult.failure(_tooLargeMessage);
    }
    if (status >= 500) {
      return const TelemetryUploadResult.failure(
        'The research server could not accept this session. Save a local export and try again later.',
      );
    }
    return const TelemetryUploadResult.failure(
      'The research server could not accept this session. Save a local export and try again later.',
    );
  }

  /// True when a `400` body reports `unsupported_schema_version`.
  static bool _mentionsUnsupportedSchema(String? body) {
    if (body == null || body.isEmpty) return false;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['error'] == 'unsupported_schema_version';
    } on FormatException {
      // A proxy or an older function may answer with plain text; fall back to
      // the code name rather than losing the diagnosis.
      return body.contains('unsupported_schema_version');
    }
  }

  /// Response bodies are read only for a machine-readable error code, so the
  /// read is capped: a hostile or accidentally huge answer must not be buffered
  /// whole.
  static const int _maxResponseBytes = 4096;

  /// Reads at most [_maxResponseBytes] of [body]. Public so the clamp is
  /// exercised directly: a single chunk can overrun the cap, and a clamped body
  /// may end mid-codepoint, so `allowMalformed` keeps the readable prefix.
  @visibleForTesting
  static Future<String> readClampedBody(Stream<List<int>> body) async {
    final bytes = <int>[];
    await for (final chunk in body) {
      // Clamp the append: a single chunk can overrun the cap on its own, so
      // testing the length after `addAll` would buffer up to 2x the cap.
      bytes.addAll(chunk.take(_maxResponseBytes - bytes.length));
      if (bytes.length >= _maxResponseBytes) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
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
      return TelemetryUploadResponse(
        response.statusCode,
        await readClampedBody(response),
      );
    } finally {
      client.close(force: true);
    }
  }
}
