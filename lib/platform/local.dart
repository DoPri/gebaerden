// Offline downloads are native-only.

export 'local_io.dart' if (dart.library.js_interop) 'local_web.dart';
