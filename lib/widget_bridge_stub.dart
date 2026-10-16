import 'models.dart';

bool get widgetsSupported => false;

Future<void> initWidgetBridge() async {}

Future<void> syncWidget(
  List<Med> meds,
  List<LogEntry> todayLogs, {
  required String profileId,
  String? title,
  String? notice,
  String? noticeMedId,
}) async {}

Future<void> showWidgetMessage(String message) async {}

Future<void> requestPinWidget() async {}
