import 'package:secretspec/secretspec.dart';
import 'package:secretspec/src/json_request.dart';

void main() {
  //TODO(bent): replace with a real example
  final version = SecretSpecFFI.instance.getAbiVersion();
  print(version);

  final foo = SecretSpecFFI.instance.resolve(requestJson: const JsonRequest());
  print(foo);
}
