import 'package:meta/meta.dart';
import 'package:secretspec/src/json_response.dart'
    show ResolutionReport, ResolveResponse;
import 'package:secretspec/src/utils.dart';

/// Which resolution shape a request asks for.
enum RequestMode {
  /// The value-carrying [ResolveResponse] (the default).
  resolve,

  /// The value-free [ResolutionReport]: per-secret status and
  /// provenance, never a value, and a missing required secret is reported as a
  /// status rather than failing the call. This is the inventory/preflight view
  /// the CLI exposes as `check --json`.
  report;

  String toJson() => switch (this) {
    .resolve => 'resolve',
    .report => 'report',
  };

  static const RequestMode defaultMode = .resolve;
}

@immutable
final class JsonRequest implements JsonSerializable {
  const JsonRequest({
    this.path,
    this.provider,
    this.profile,
    this.scope,
    this.reason,
    this.noValues = false,
    this.mode = .defaultMode,
  });

  final String? path;
  final String? provider;
  final String? profile;
  final String? scope;
  final String? reason;
  final bool noValues;
  final RequestMode mode;

  @override
  Map<String, dynamic> toJson() {
    return {
      'path': ?path,
      'provider': ?provider,
      'profile': ?profile,
      'scope': ?scope,
      'reason': ?reason,
      'no_values': noValues,
      'mode': mode.toJson(),
    };
  }
}
