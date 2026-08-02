import 'package:meta/meta.dart';
import 'package:secretspec/src/json_request.dart' show RequestMode;

@immutable
sealed class Response implements Envelope {
  factory Response.fromJson(RequestMode mode, Map<String, dynamic> json) =>
      switch (mode) {
        .resolve => ResolveResponse.fromJson(json),
        .report => ResolutionReport.fromJson(json),
      };
}

@immutable
final class Error implements Envelope {
  const Error({required this.kind, required this.message});
  factory Error.fromJson(Map<String, dynamic> json) =>
      Error(kind: json['kind'] as String, message: json['message'] as String);

  final String kind;
  final String message;

  @override
  String toString() => 'Error(kind: $kind,message: $message)';
}

/// Version of the [ResolveResponse] wire format.
const int resolveSchemaVersion = 2;

/// Where a resolved value came from.
enum ResolvedSource {
  /// Returned by a storage provider.
  provider,

  /// Freshly minted by the secret's `generate` config.
  generated,

  /// The manifest's committed `default` value.
  default_,

  /// Derived from other declared secrets using a strict template.
  ///
  /// Available since SecretSpec 0.16.
  composed;

  /// Parses the snake_case wire value into a [ResolvedSource].
  static ResolvedSource fromJson(String value) {
    switch (value) {
      case 'provider':
        return .provider;
      case 'generated':
        return .generated;
      case 'default':
        return .default_;
      case 'composed':
        return .composed;
      default:
        throw ArgumentError('Unknown ResolvedSource: $value');
    }
  }
}

/// Wraps a sensitive string value so it can't be accidentally leaked via
/// `toString()`, string interpolation, logging, or debug printing.
@immutable
class RedactedString {
  const RedactedString(this._value);
  final String _value;
  String get reveal => _value;

  @override
  String toString() => '<redacted>';

  @override
  bool operator ==(Object other) =>
      other is RedactedString && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}

/// One resolved secret. Exactly one of [value] or [path] is set: [path] when
/// the secret is materialized to a temp file (`as_path`), [value] otherwise.
@immutable
final class ResolvedSecret {
  const ResolvedSecret({
    required this.asPath,
    required this.source,
    this.value,
    this.path,
    this.sourceProvider,
  });

  factory ResolvedSecret.fromJson(Map<String, dynamic> json) {
    return ResolvedSecret(
      value: switch (json['value'] as String?) {
        final v? => RedactedString(v),
        null => null,
      },
      path: json['path'] as String?,
      asPath: json['as_path'] as bool,
      source: ResolvedSource.fromJson(json['source'] as String),
      sourceProvider: json['source_provider'] as String?,
    );
  }

  /// The secret value, when exposed inline.
  final RedactedString? value;

  /// Path to the temp file holding the value, when `as_path` is set.
  final String? path;

  /// Whether this secret is exposed as a file path rather than inline.
  final bool asPath;

  /// Whether the value came from a provider, a generator, or a default.
  final ResolvedSource source;

  /// Credential-free URI of the provider that answered, when [source] is
  /// [ResolvedSource.provider].
  final String? sourceProvider;

  @override
  String toString() {
    return 'ResolvedSecret('
        'value: $value'
        'path: $path, '
        'asPath: $asPath, '
        'source: $source, '
        'sourceProvider: $sourceProvider'
        ')';
  }
}

/// A complete value-carrying resolution result for one profile.
@immutable
final class ResolveResponse implements Response {
  const ResolveResponse({
    required this.schemaVersion,
    required this.provider,
    required this.profile,
    required this.secrets,
    required this.missingRequired,
    required this.missingOptional,
    this.scope,
  });

  factory ResolveResponse.fromJson(Map<String, dynamic> json) {
    return ResolveResponse(
      schemaVersion: json['schema_version'] as int,
      provider: json['provider'] as String,
      profile: json['profile'] as String,
      scope: json['scope'] as String?,
      secrets: Map.unmodifiable(<String, ResolvedSecret>{
        if (json['secrets'] != null)
          for (final MapEntry(:key, :Map<String, dynamic> value)
              in (json['secrets'] as Map<String, dynamic>).entries)
            key: .fromJson(value),
      }),
      missingRequired: List.unmodifiable([
        if (json['missing_required'] != null)
          for (final e in json['missing_required'] as List<dynamic>)
            e as String,
      ]),
      missingOptional: List.unmodifiable([
        if (json['missing_optional'] != null)
          for (final e in json['missing_optional'] as List<dynamic>)
            e as String,
      ]),
    );
  }

  /// Wire-format version; see [resolveSchemaVersion].
  final int schemaVersion;

  /// Credential-free URI of the provider the resolution reported against.
  /// Empty when no provider was contacted, which happens when a scope's
  /// intersection with the selected profile is empty and there is nothing to
  /// resolve.
  final String provider;

  /// The profile that was resolved.
  final String profile;

  /// The active secret scope, when resolution was scoped (`--scope`,
  /// `SECRETSPEC_SCOPE`, or the SDK builder). `null` means the whole profile
  /// resolved.
  final String? scope;

  /// Resolved secrets by name. Empty when a required secret is missing.
  final Map<String, ResolvedSecret> secrets;

  /// Required secrets that were not found anywhere. Non-empty means the
  /// resolution failed; [secrets] is then empty.
  final List<String> missingRequired;

  /// Optional secrets that were not found.
  final List<String> missingOptional;
}

@immutable
sealed class Envelope {
  factory Envelope.fromJson(RequestMode mode, Map<String, dynamic> json) {
    return switch ((json['ok'], json['response'], json['error'])) {
      (null, _, _) => throw const FormatException('Missing `ok` field'),

      (true, null, _) => throw const FormatException('Missing response field'),
      (true, final Map<String, dynamic> response, _) => Response.fromJson(
        mode,
        response,
      ),

      (false, _, null) => throw const FormatException('Missing `error` field'),
      (false, _, final Map<String, dynamic> error) => Error.fromJson(error),

      _ => throw const FormatException(
        'Could not parse `ok` field to a boolean',
      ),
    };
  }
}

/// Wire-format version; see [ResolutionReport.schemaVersion].
const int resolutionReportSchemaVersion = 1;

/// How a single declared secret resolved.
enum ResolutionStatus {
  /// A value was produced (from a provider, a generator, or a default).
  resolved('resolved'),

  /// Required by the active profile but not found anywhere.
  missingRequired('missing_required'),

  /// Optional and not found; resolution still succeeds overall.
  missingOptional('missing_optional');

  const ResolutionStatus(this.wireValue);

  factory ResolutionStatus.fromJson(String json) {
    return ResolutionStatus.values.firstWhere(
      (v) => v.wireValue == json,
      orElse: () => throw ArgumentError('Unknown ResolutionStatus: $json'),
    );
  }

  /// The `snake_case` value used on the wire.
  final String wireValue;
}

/// Which presence rule failed.
///
/// Note: the Rust source did not provide the definition of `ConstraintKind`;
/// this is deserialized as an opaque string to remain forward-compatible.
/// Replace with a proper enum once the Rust variants are known.
typedef ConstraintKind = String;

/// A failed cross-secret presence constraint.
///
/// `secrets` is the configured group and `present` is the subset that
/// resolved. Values are never included.
///
/// Available since SecretSpec 0.17.
@immutable
final class ConstraintViolation {
  const ConstraintViolation({
    required this.kind,
    required this.group,
    required this.secrets,
    required this.present,
  });

  factory ConstraintViolation.fromJson(Map<String, dynamic> json) {
    return ConstraintViolation(
      kind: json['kind'] as String,
      group: json['group'] as String,
      secrets: List.unmodifiable([
        if (json['secrets'] != null)
          for (final e in json['secrets'] as List<dynamic>) e as String,
      ]),
      present: List.unmodifiable([
        if (json['present'] != null)
          for (final e in json['present'] as List<dynamic>) e as String,
      ]),
    );
  }

  /// Which presence rule failed.
  final ConstraintKind kind;

  /// The group name declared by its member secrets.
  final String group;

  /// All secret names in the configured group.
  final List<String> secrets;

  /// Group members that resolved.
  final List<String> present;
}

/// The resolution outcome for one declared secret. Never carries the value.
@immutable
final class SecretResolution {
  const SecretResolution({
    required this.name,
    required this.status,
    required this.required,
    required this.defaultApplied,
    required this.generated,
    required this.asPath,
    this.sourceProvider,
  });

  factory SecretResolution.fromJson(Map<String, dynamic> json) {
    return SecretResolution(
      name: json['name'] as String,
      status: ResolutionStatus.fromJson(json['status'] as String),
      required: json['required'] as bool,
      sourceProvider: json['source_provider'] as String?,
      defaultApplied: json['default_applied'] as bool,
      generated: json['generated'] as bool,
      asPath: json['as_path'] as bool,
    );
  }

  /// The declared secret name (the `UPPER_SNAKE` key from the manifest).
  final String name;

  /// Whether the secret resolved, and if not, whether that is an error.
  final ResolutionStatus status;

  /// Whether the secret is *declared* required in the active profile: `true`
  /// when it is marked `required = true` or has neither a `default` nor a
  /// `generate`. A secret carrying a committed `default`/`generate` is not
  /// required (it always resolves), even when written as `required = true` in
  /// one profile and overridden with a default in another. Orthogonal to
  /// [status], which reports whether it actually resolved.
  final bool required;

  /// Credential-free URI of the provider that actually answered, when the
  /// value came from a provider. `null` when generated, defaulted, or
  /// missing.
  final String? sourceProvider;

  /// Whether the value came from the manifest's committed `default`.
  final bool defaultApplied;

  /// Whether the value was freshly minted by the secret's `generate` config.
  final bool generated;

  /// Whether the value is materialized to a temp file and exposed as a path.
  final bool asPath;
}

/// A complete, value-free snapshot of one resolution pass over a profile.
@immutable
final class ResolutionReport implements Response {
  const ResolutionReport({
    required this.schemaVersion,
    required this.provider,
    required this.profile,
    required this.secrets,
    required this.constraintViolations,
    this.scope,
  });

  factory ResolutionReport.fromJson(Map<String, dynamic> json) {
    return ResolutionReport(
      schemaVersion: json['schema_version'] as int,
      provider: json['provider'] as String,
      profile: json['profile'] as String,
      scope: json['scope'] as String?,
      secrets: List.unmodifiable([
        if (json['secrets'] != null)
          for (final e in json['secrets'] as List<dynamic>)
            SecretResolution.fromJson(e as Map<String, dynamic>),
      ]),
      constraintViolations: List.unmodifiable([
        if (json['constraint_violations'] != null)
          for (final e in json['constraint_violations'] as List<dynamic>)
            ConstraintViolation.fromJson(e as Map<String, dynamic>),
      ]),
    );
  }

  /// Wire-format version; see [resolutionReportSchemaVersion].
  final int schemaVersion;

  /// Credential-free URI of the provider resolution reported against. Empty
  /// when no provider was contacted, which happens when a scope's
  /// intersection with the selected profile is empty and there is nothing to
  /// resolve.
  final String provider;

  /// The profile that was resolved.
  final String profile;

  /// The active secret scope, when resolution was scoped (`--scope`,
  /// `SECRETSPEC_SCOPE`, or the SDK builder). `null` means the whole profile
  /// resolved.
  final String? scope;

  /// One entry per declared secret, sorted by name for deterministic output.
  final List<SecretResolution> secrets;

  /// Cross-secret presence constraints that failed.
  ///
  /// Available since SecretSpec 0.17. Empty when all constraints pass.
  final List<ConstraintViolation> constraintViolations;
}
