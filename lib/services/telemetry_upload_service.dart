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

  /// True when the build supplied *something* to upload to.
  ///
  /// Deliberately weaker than "usable": a present-but-insecure endpoint must
  /// still reach [TelemetryUploadService.upload] so the user is told the
  /// specific reason instead of a generic "not configured". Whether the
  /// endpoint may actually be used is [validateTelemetryEndpoint]'s decision.
  bool get isConfigured =>
      ingestUrl.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}

/// Why the configured ingest endpoint may or may not be used.
enum TelemetryEndpointStatus {
  valid,
  notConfigured,
  insecureScheme,
  malformed,
  missingHost,
  hasCredentials,
}

/// Validates the build-time ingest endpoint. Pure: nothing outside the
/// arguments is read, and [debugMode] is injected so both sides of the
/// debug-only exception can be asserted without a compile-time constant.
///
/// Rules: `https` only; an absolute URI with a host; no embedded credentials.
/// A URL is never rewritten or normalised — a defective one is reported, not
/// repaired. Path, port and query are unconstrained, because a Supabase
/// function URL is `https://<ref>.supabase.co/functions/v1/ingest-telemetry`.
TelemetryEndpointStatus validateTelemetryEndpoint({
  required String ingestUrl,
  required String publishableKey,
  bool debugMode = kDebugMode,
}) {
  if (ingestUrl.trim().isEmpty || publishableKey.trim().isEmpty) {
    return TelemetryEndpointStatus.notConfigured;
  }
  // Reject, never repair: padding is reported so a mis-quoted --dart-define
  // surfaces instead of being half-mended.
  if (ingestUrl != ingestUrl.trim() ||
      publishableKey != publishableKey.trim()) {
    return TelemetryEndpointStatus.malformed;
  }
  final uri = Uri.tryParse(ingestUrl);
  if (uri == null || !uri.hasScheme) {
    // A scheme-less host ("example.com/ingest") is not an absolute URL.
    return TelemetryEndpointStatus.malformed;
  }
  if (uri.scheme.toLowerCase() != 'https' &&
      !_isDebugLoopback(uri, debugMode: debugMode)) {
    return TelemetryEndpointStatus.insecureScheme;
  }
  if (uri.host.isEmpty) return TelemetryEndpointStatus.missingHost;
  if (uri.userInfo.isNotEmpty) {
    return TelemetryEndpointStatus.hasCredentials;
  }
  // shortcut: no host-shape rule and no port-range check, so a syntactically
  // odd host (`https://.com`, `https://example..com`, `https://exam ple.com`)
  // and a port above 65535 still count as valid — the first request then fails
  // as "could not be reached". This URL is a maintainer-set --dart-define, so a
  // typo is caught in the build, not by the app; add a host rule if the endpoint
  // ever becomes user- or remote-supplied.
  return TelemetryEndpointStatus.valid;
}

/// Debug-only, deliberately narrow exception: plain `http` is accepted for a
/// loopback host so a local ingest function can be exercised from a debug
/// build. A release build rejects loopback `http` like any other insecure
/// scheme, and every non-loopback `http` host is rejected in both modes.
bool _isDebugLoopback(Uri uri, {required bool debugMode}) {
  if (!debugMode || uri.scheme.toLowerCase() != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}

/// One user-facing sentence per failing status, or `null` when the endpoint is
/// [TelemetryEndpointStatus.valid]. No message contains the endpoint, the key,
/// or any part of either.
String? telemetryEndpointMessage(TelemetryEndpointStatus status) =>
    switch (status) {
      TelemetryEndpointStatus.valid => null,
      TelemetryEndpointStatus.notConfigured =>
        'Research upload has not been configured for this build.',
      TelemetryEndpointStatus.insecureScheme =>
        'Research upload requires an HTTPS address. This build is configured '
            'with an insecure endpoint, so the session was not uploaded. Save '
            'a local export.',
      TelemetryEndpointStatus.malformed =>
        'The configured research upload address is not a valid HTTPS address, '
            'so the session was not uploaded. Save a local export.',
      TelemetryEndpointStatus.missingHost =>
        'The configured research upload address does not name a server, so '
            'the session was not uploaded. Save a local export.',
      TelemetryEndpointStatus.hasCredentials =>
        'The configured research upload address contains an embedded username '
            'or password, so it was refused and the session was not uploaded. '
            'Save a local export.',
    };

/// Research context supplied by a researcher for one explicitly uploaded
/// session. It deliberately has no free-text field to avoid accidental PII.
///
/// [uploadToken] is a study credential, not participant data. It crosses the
/// wire in the upload header only: never in [toJson], never in a preference, an
/// export file, telemetry or a log line, and [toString] redacts it so an
/// accidental `print` of this object cannot leak it.
class ResearchSessionMetadata {
  const ResearchSessionMetadata({
    required this.participantCode,
    required this.studyScenario,
    required this.uploadToken,
  });

  final String participantCode;
  final String studyScenario;

  /// Researcher-supplied credential, in memory for the request only.
  final String uploadToken;

  bool get isValid =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(participantCode) &&
      studyScenario.trim().isNotEmpty &&
      studyScenario.trim().length <= 80;

  /// UX courtesy only — 43–128 token-safe characters, no padding. Mirrors
  /// `isValidUploadTokenShape` in the ingest function, which is the trust
  /// boundary; a token that passes here is still checked server-side.
  bool get hasValidUploadToken =>
      RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(uploadToken);

  Map<String, dynamic> toJson() => {
    'participantCode': participantCode.trim(),
    'studyScenario': studyScenario.trim(),
  };

  @override
  String toString() =>
      'ResearchSessionMetadata(participantCode: $participantCode, '
      'studyScenario: $studyScenario)';
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
    this.debugMode = kDebugMode,
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

  /// Header carrying the researcher-issued study upload token. The token is not
  /// a build-time define: it is entered per upload and never persisted.
  static const String uploadTokenHeaderName = 'X-Eyecue-Upload-Token';

  /// Local refusal text; reused when the server answers `413` itself.
  static const String _tooLargeMessage =
      'This session is too large to upload. Save a local export to keep the data.';

  final TelemetryUploadConfiguration _configuration;
  final TelemetryExportService _exportService;
  final TelemetryUploadSender _sender;
  final DateTime Function() _clock;

  /// Injected so a test can assert both sides of the debug-only loopback
  /// exception; defaults to the compile-time constant. Public only so the
  /// constructor can take it as an initializing formal, like [maxBodyBytes].
  final bool debugMode;

  /// Effective body limit; a test may lower it to drive the refusal branch.
  ///
  /// The annotation only documents that tests are the intended caller: it does
  /// not prevent application code from passing a wider value through the named
  /// constructor parameter. Nothing here enforces the 2 000 000 bound on a
  /// caller that widens it, so keeping the default is a convention, not a
  /// guarantee.
  @visibleForTesting
  final int maxBodyBytes;

  /// True when the build supplied an endpoint and a key at all — not that the
  /// endpoint is usable. Callers gate the *button* on this so a
  /// present-but-insecure address still reaches [upload] and is explained;
  /// [upload] itself refuses anything that is not [TelemetryEndpointStatus.valid].
  bool get isConfigured => _configuration.isConfigured;

  /// Whether the configured endpoint may be used, and why not when it may not.
  TelemetryEndpointStatus get endpointStatus => validateTelemetryEndpoint(
    ingestUrl: _configuration.ingestUrl,
    publishableKey: _configuration.publishableKey,
    debugMode: debugMode,
  );

  Future<TelemetryUploadResult> upload({
    required TelemetryService telemetry,
    required ResearchSessionMetadata metadata,
    AppSettings? settings,
  }) async {
    final status = endpointStatus;
    if (status != TelemetryEndpointStatus.valid) {
      // Refused before anything is read from the session or sent: no request is
      // made and the in-memory telemetry is left exactly as it was.
      return TelemetryUploadResult.failure(telemetryEndpointMessage(status)!);
    }
    if (!metadata.isValid) {
      return const TelemetryUploadResult.failure(
        'Enter a valid participant code and study scenario.',
      );
    }
    if (!metadata.hasValidUploadToken) {
      // Refused locally as a courtesy: the token shape, not its validity, is all
      // the client can judge. Nothing is sent and the session is untouched.
      return const TelemetryUploadResult.failure(
        'Enter the study upload token supplied by the study coordinator. The '
        'session was not uploaded. Save a local export.',
      );
    }

    // Already validated above: absolute, `https` (or the debug loopback case),
    // hosted and credential-free — so this parse cannot disagree with it.
    final uri = Uri.parse(_configuration.ingestUrl);

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
            // The study credential. Kept out of the body, the export and every
            // message; only the server hashes it.
            uploadTokenHeaderName: metadata.uploadToken,
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
    // A study-token refusal has its own actionable answer and is never folded
    // into the generic authorisation message: "your token expired" and "this
    // build is not authorised" need different actions from the researcher.
    final tokenFailure = _uploadTokenFailure(response.body);
    if (tokenFailure != null) return tokenFailure;
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

  /// Every code the ingest function may answer with. Used only to recover a
  /// code from a plain-text body.
  static const List<String> _errorCodes = [
    'unsupported_schema_version',
    'missing_upload_token',
    'invalid_upload_token',
    'expired_upload_token',
    'revoked_upload_token',
    'upload_token_exhausted',
    'participant_mismatch',
    'rate_limited',
  ];

  /// The machine-readable `error` code of a response body, or `null`.
  ///
  /// Bodies are read for the code only and never shown to the user, so no
  /// server-controlled text reaches the screen.
  static String? _errorCode(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
      return null;
    } on FormatException {
      // A proxy or an older function may answer with plain text; fall back to
      // the code name rather than losing the diagnosis.
      for (final code in _errorCodes) {
        if (body.contains(code)) return code;
      }
      return null;
    }
  }

  /// True when a `400` body reports `unsupported_schema_version`.
  static bool _mentionsUnsupportedSchema(String? body) =>
      _errorCode(body) == 'unsupported_schema_version';

  /// One distinct, actionable message per study-upload-token refusal, or `null`
  /// when the body carries no token code.
  ///
  /// Every message is a fixed sentence: the token is never interpolated, so no
  /// failure path can show (or log) it. Each keeps the local-export fallback and
  /// leaves the in-memory session untouched.
  static TelemetryUploadResult? _uploadTokenFailure(
    String? body,
  ) => switch (_errorCode(body)) {
    'missing_upload_token' => const TelemetryUploadResult.failure(
      'No study upload token was sent. Enter the token the study coordinator gave you; the session was not uploaded. Save a local export.',
    ),
    'invalid_upload_token' => const TelemetryUploadResult.failure(
      'The research server did not recognise the study upload token. Check it with the study coordinator; the session was not uploaded. Save a local export.',
    ),
    'expired_upload_token' => const TelemetryUploadResult.failure(
      'The study upload token has expired. Ask the study coordinator for a new one; the session was not uploaded. Save a local export.',
    ),
    'revoked_upload_token' => const TelemetryUploadResult.failure(
      'The study upload token has been revoked. Ask the study coordinator for a new one; the session was not uploaded. Save a local export.',
    ),
    'upload_token_exhausted' => const TelemetryUploadResult.failure(
      'This study upload token has no uploads left. Ask the study coordinator for a new one; the session was not uploaded. Save a local export.',
    ),
    'participant_mismatch' => const TelemetryUploadResult.failure(
      'The study upload token belongs to a different participant code. Check both values; the session was not uploaded. Save a local export.',
    ),
    'rate_limited' => const TelemetryUploadResult.failure(
      'Too many upload attempts from this token. Wait a few minutes and try again; the session was not uploaded. Save a local export to keep the data.',
    ),
    _ => null,
  };

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
