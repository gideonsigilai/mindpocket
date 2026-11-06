import 'package:flutter/foundation.dart';

import 'logger.dart';

/// Isolate helpers.
///
/// sherpa-onnx FFI bindings must be initialised in each isolate and the model
/// objects are not Sendable, so transcription runs on a background isolate that
/// opens the model itself. This wrapper keeps the call sites honest about it.
Future<R> computeOnBackground<M, R>(ComputeCallback<M, R> callback, M message) {
  if (kIsWeb) {
    // Android and iOS use real isolates; web has no native isolate runtime.
    logWarn('Background isolate unavailable on web; running inline.');
    return Future<R>.value(callback(message));
  }
  return compute(callback, message);
}
