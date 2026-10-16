// Home-screen widget support. The real implementation only exists on
// Android; the web build (used on iPhone) gets no-op stubs.
export 'widget_bridge_stub.dart' if (dart.library.io) 'widget_bridge_android.dart';
