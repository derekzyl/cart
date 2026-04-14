import "package:flutter_riverpod/flutter_riverpod.dart";

import "../core/telemetry_model.dart";
import "connection_provider.dart";

final StreamProvider<Telemetry> telemetryProvider = StreamProvider<Telemetry>((Ref ref) async* {
  final service = ref.watch(websocketServiceProvider);
  Telemetry latest = Telemetry.initial;
  yield latest;
  await for (final String raw in service.messages) {
    final Telemetry? parsed = Telemetry.tryParse(raw);
    if (parsed != null) {
      latest = parsed;
      yield latest;
    }
  }
});
