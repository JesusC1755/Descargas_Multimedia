import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

final talker = TalkerFlutter.init(
  settings: TalkerSettings(
    maxHistoryItems: 500,
    useConsoleLogs: kDebugMode,
  ),
);
