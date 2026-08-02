import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:secretspec/src/json_request.dart';
import 'package:secretspec/src/json_response.dart';

//TODO(bent): use this name resolution
// ignore: unused_element
String _dynamicLibraryName() {
  if (Platform.isMacOS) {
    return 'libsecretspec_ffi.dylib';
  }

  if (Platform.isWindows) {
    return 'libsecretspec_ffi.dll';
  }
  return 'libsecretspec_ffi.so';
}

typedef SecretspecAbiVersionDart = ffi.Pointer<Utf8> Function();
// const char *secretspec_abi_version(void);
typedef SecretspecAbiVersionNative = ffi.Pointer<Utf8> Function();

typedef SecretspecFreeDart = void Function(ffi.Pointer<Utf8> ptr);
// void secretspec_free(char *ptr);
typedef SecretspecFreeNative = ffi.Void Function(ffi.Pointer<Utf8> ptr);

typedef SecretspecResolveDart =
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> requestJson);
// char *secretspec_resolve(const char *request_json);
typedef SecretspecResolveNative =
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> requestJson);

class SecretSpecFFI {
  factory SecretSpecFFI._build() {
    final envVars = Platform.environment;

    final envffiLib = envVars['SECRETSPEC_FFI_LIB'];
    if (envffiLib == null || envffiLib.isEmpty) {
      throw UnimplementedError('TODO: implement fallback');
    }
    final dylib = ffi.DynamicLibrary.open(envffiLib);
    return SecretSpecFFI._internal(dylib: dylib);
  }
  //TODO(bent): investigate use of isLeaf
  SecretSpecFFI._internal({required this._dylib})
    : _ffiAbiVersion = _dylib
          .lookupFunction<SecretspecAbiVersionNative, SecretspecAbiVersionDart>(
            'secretspec_abi_version',
            isLeaf: true,
          ),
      _ffiFree = _dylib
          .lookupFunction<SecretspecFreeNative, SecretspecFreeDart>(
            'secretspec_free',
            isLeaf: true,
          ),
      _ffiResolve = _dylib
          .lookupFunction<SecretspecResolveNative, SecretspecResolveDart>(
            'secretspec_resolve',
            isLeaf: false,
          );

  /// the one and only instance of this singleton
  static final SecretSpecFFI instance = SecretSpecFFI._build();
  final ffi.DynamicLibrary _dylib;
  final SecretspecAbiVersionDart _ffiAbiVersion;

  final SecretspecFreeDart _ffiFree;

  final SecretspecResolveDart _ffiResolve;

  void close() => _dylib.close();

  String getAbiVersion() {
    final response = _ffiAbiVersion();
    return response.toDartString(length: null);
  }

  Envelope resolve({required JsonRequest requestJson}) {
    ffi.Pointer<Utf8>? responseJson;
    try {
      responseJson = _ffiResolve(json.encode(requestJson).toNativeUtf8());
      print('request: ${json.encode(requestJson)}');
      final responseJsonDart = responseJson.toDartString(length: null);
      return Envelope.fromJson(
        requestJson.mode,
        json.decode(responseJsonDart) as Map<String, dynamic>,
      );
    } finally {
      if (responseJson != null) {
        _ffiFree(responseJson);
      }
    }
  }
}
