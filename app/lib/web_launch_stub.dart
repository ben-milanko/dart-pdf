import 'incoming_file.dart';

/// Non-web platforms have no browser launch queue — nothing to drain.
void startWebLaunchQueue(void Function(IncomingFile) onFile) {}
