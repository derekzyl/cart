import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "providers/connection_provider.dart";
import "providers/settings_provider.dart";
import "screens/connection_screen.dart";
import "screens/controller_screen.dart";
import "theme/app_theme.dart";

class RobotControlApp extends ConsumerWidget {
  const RobotControlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    final ConnectionUiState connection = ref.watch(connectionProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Robot Controller",
      theme: AppTheme.themeData,
      home: connection.status == ConnectionStatus.connected
          ? const ControllerScreen()
          : const ConnectionScreen(),
    );
  }
}
