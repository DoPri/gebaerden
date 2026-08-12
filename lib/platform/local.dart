// Offline downloads are a native-only feature.

export 'local_io.dart' if (dart.library.js_interop) 'local_web.dart';
