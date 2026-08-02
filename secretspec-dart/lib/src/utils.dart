import 'dart:convert';

import 'package:meta/meta.dart' show mustBeOverridden;

///indicates that the class is serializable by [json.encode]
abstract interface class JsonSerializable {
  /// Function used to Encode a class to json.
  @mustBeOverridden
  Map<String, dynamic> toJson();
}
