import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../providers/connection_provider.dart";
import "../providers/settings_provider.dart";
import "../providers/wifi_provider.dart";
import "../theme/app_theme.dart";
import "shared/clipped_corner_box.dart";

class WifiSetupSheet extends ConsumerStatefulWidget {
  const WifiSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: const WifiSetupSheet(),
      ),
    );
  }

  @override
  ConsumerState<WifiSetupSheet> createState() => _WifiSetupSheetState();
}

class _WifiSetupSheetState extends ConsumerState<WifiSetupSheet> {
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _ssidController = TextEditingController();
    _passwordController = TextEditingController();
    // Auto scan on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(wifiProvider.notifier).scanNetworks();
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onSelectNetwork(WifiNetwork network) {
    setState(() {
      _ssidController.text = network.ssid;
    });
  }

  Future<void> _connect() async {
    final String ssid = _ssidController.text.trim();
    final String pass = _passwordController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select or enter a Wi-Fi network name (SSID)"),
          backgroundColor: AppTheme.kRecord,
        ),
      );
      return;
    }
    await ref.read(wifiProvider.notifier).connectSharedWifi(ssid, pass);
  }

  Future<void> _switchToNewIp(String newIp) async {
    final ControlSettings s = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(s.copyWith(ip: newIp));
    ref.read(connectionProvider.notifier).connect(newIp, s.port);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Switched app target to $newIp and reconnecting!"),
        backgroundColor: AppTheme.kAccent,
      ),
    );
  }

  Future<void> _confirmResetToHotspot() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppTheme.kPanel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppTheme.kStop),
          borderRadius: BorderRadius.circular(6),
        ),
        title: Text("RESET TO HOTSPOT?", style: AppTheme.displayNum(14, color: AppTheme.kStop)),
        content: Text(
          "This will disconnect the robot from the shared Wi-Fi and restart the built-in hotspot (CartRobot_Setup at 192.168.4.1).",
          style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text("CANCEL", style: AppTheme.labelUi(12, color: AppTheme.kTextSec)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.kStop),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text("RESET", style: AppTheme.labelUi(12, color: Colors.white, weight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(wifiProvider.notifier).resetToHotspot();
      final ControlSettings s = ref.read(settingsProvider);
      await ref.read(settingsProvider.notifier).update(s.copyWith(ip: "192.168.4.1"));
      ref.read(connectionProvider.notifier).connect("192.168.4.1", s.port);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Robot reset to Hotspot mode (192.168.4.1)."),
          backgroundColor: AppTheme.kStop,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final WifiState wifiState = ref.watch(wifiProvider);
    final ConnectionUiState conn = ref.watch(connectionProvider);
    final bool isScanning = wifiState.status == WifiConfigStatus.scanning;
    final bool isConnecting = wifiState.status == WifiConfigStatus.connecting;
    final bool hasNewIp = wifiState.newIp != null && wifiState.status == WifiConfigStatus.connected;

    return ClippedCornerBox(
      cutSize: 6,
      backgroundColor: AppTheme.kPanel,
      borderColor: AppTheme.kBorder,
      topAccentColor: AppTheme.kAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              color: AppTheme.kAccent.withValues(alpha: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.wifi_rounded, color: AppTheme.kAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  "ROBOT WI-FI CONFIGURATION",
                  style: AppTheme.displayNum(13, color: AppTheme.kAccent),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.kTextSec, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.kBorder),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: <Widget>[
                // Current Network Status Badge
                ClippedCornerBox(
                  cutSize: 4,
                  backgroundColor: AppTheme.kSurface,
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (conn.host == "192.168.4.1")
                              ? AppTheme.kStop.withValues(alpha: 0.2)
                              : AppTheme.kAccent.withValues(alpha: 0.2),
                          border: Border.all(
                            color: (conn.host == "192.168.4.1") ? AppTheme.kStop : AppTheme.kAccent,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          (conn.host == "192.168.4.1") ? "HOTSPOT MODE" : "SHARED WI-FI",
                          style: AppTheme.monoData(
                            10,
                            color: (conn.host == "192.168.4.1") ? AppTheme.kStop : AppTheme.kAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              "Current IP: ${conn.host}:${conn.port}",
                              style: AppTheme.monoData(11, color: AppTheme.kTextPri),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Target: ${(conn.host == "192.168.4.1") ? "CartRobot_Setup (AP)" : "Local LAN (STA)"}",
                              style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Helper tip card: Hotspot credentials & hardware reset button guide
                ClippedCornerBox(
                  cutSize: 4,
                  backgroundColor: AppTheme.kBorder.withValues(alpha: 0.2),
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.info_outline_rounded, color: AppTheme.kAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Robot Hotspot: CartRobot_Setup • Password: cartsetup\nHardware Reset: Hold ESP32 BOOT button (GPIO 0) or BTN1 for 2s to restore Hotspot.",
                          style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Success / New IP notification card if connected
                if (hasNewIp) ...<Widget>[
                  ClippedCornerBox(
                    cutSize: 6,
                    backgroundColor: AppTheme.kAccent.withValues(alpha: 0.15),
                    borderColor: AppTheme.kAccent,
                    topAccentColor: AppTheme.kAccent,
                    glowColor: AppTheme.kAccent,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.check_circle_rounded, color: AppTheme.kAccent, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              "ROBOT CONNECTED TO WI-FI!",
                              style: AppTheme.labelUi(12, color: AppTheme.kAccent, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "New IP Address: ${wifiState.newIp}\n(Displaying on Robot LCD right now)",
                          style: AppTheme.monoData(11, color: AppTheme.kTextPri),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _switchToNewIp(wifiState.newIp!),
                          child: ClippedCornerBox(
                            cutSize: 4,
                            backgroundColor: AppTheme.kGlow,
                            borderColor: AppTheme.kAccent,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: Text(
                                "SWITCH APP TO NEW IP & RECONNECT",
                                style: AppTheme.labelUi(11, color: Colors.black, weight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Error alert if failed
                if (wifiState.status == WifiConfigStatus.failed && wifiState.errorMessage != null) ...<Widget>[
                  ClippedCornerBox(
                    cutSize: 4,
                    backgroundColor: AppTheme.kRecord.withValues(alpha: 0.15),
                    borderColor: AppTheme.kRecord,
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.error_outline_rounded, color: AppTheme.kRecord, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            wifiState.errorMessage!,
                            style: AppTheme.labelUi(11, color: AppTheme.kRecord),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Section Title: Connect to Shared Wi-Fi
                Row(
                  children: <Widget>[
                    Text("CONNECT TO SHARED WI-FI", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: isScanning ? null : () => ref.read(wifiProvider.notifier).scanNetworks(),
                      icon: isScanning
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.kAccent),
                            )
                          : const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.kAccent),
                      label: Text(
                        isScanning ? "Scanning…" : "Scan Networks",
                        style: AppTheme.labelUi(10, color: AppTheme.kAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Scanned Networks List
                if (wifiState.availableNetworks.isNotEmpty) ...<Widget>[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: AppTheme.kSurface,
                      border: Border.all(color: AppTheme.kBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: wifiState.availableNetworks.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1, color: AppTheme.kBorder),
                      itemBuilder: (BuildContext context, int i) {
                        final WifiNetwork n = wifiState.availableNetworks[i];
                        final bool isSelected = _ssidController.text == n.ssid;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          leading: Icon(
                            n.secure ? Icons.wifi_password_rounded : Icons.wifi_rounded,
                            size: 16,
                            color: isSelected ? AppTheme.kAccent : AppTheme.kTextSec,
                          ),
                          title: Text(
                            n.ssid,
                            style: AppTheme.labelUi(
                              11,
                              color: isSelected ? AppTheme.kAccent : AppTheme.kTextPri,
                              weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          trailing: Text(
                            "${n.rssi} dBm",
                            style: AppTheme.monoData(9, color: AppTheme.kTextSec),
                          ),
                          onTap: () => _onSelectNetwork(n),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // SSID Input field
                ClippedCornerBox(
                  cutSize: 5,
                  backgroundColor: AppTheme.kSurface,
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: TextField(
                    controller: _ssidController,
                    style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                    cursorColor: AppTheme.kTextPri,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: "Wi-Fi Name (SSID)",
                      labelStyle: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                      hintText: "Select above or enter network name",
                      hintStyle: AppTheme.labelUi(11, color: AppTheme.kDim),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Password Input field
                ClippedCornerBox(
                  cutSize: 5,
                  backgroundColor: AppTheme.kSurface,
                  borderColor: AppTheme.kBorder,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: AppTheme.labelUi(12, color: AppTheme.kTextPri),
                    cursorColor: AppTheme.kTextPri,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: "Wi-Fi Password",
                      labelStyle: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                      hintText: "Enter password (leave blank if open)",
                      hintStyle: AppTheme.labelUi(11, color: AppTheme.kDim),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 16,
                          color: AppTheme.kTextSec,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Connect Button
                GestureDetector(
                  onTap: isConnecting ? null : _connect,
                  child: ClippedCornerBox(
                    cutSize: 6,
                    backgroundColor: isConnecting
                        ? AppTheme.kDim
                        : AppTheme.kAccent.withValues(alpha: 0.2),
                    borderColor: AppTheme.kAccent,
                    topAccentColor: AppTheme.kAccent,
                    glowColor: isConnecting ? null : AppTheme.kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: isConnecting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.kAccent),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "CONNECTING ROBOT TO WI-FI…",
                                  style: AppTheme.labelUi(11, color: AppTheme.kAccent, weight: FontWeight.w700),
                                ),
                              ],
                            )
                          : Text(
                              "CONNECT ROBOT TO WI-FI",
                              style: AppTheme.labelUi(12, color: AppTheme.kAccent, weight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppTheme.kBorder),
                const SizedBox(height: 12),

                // Fallback / Reset Section
                Text("RESET / HOTSPOT RECOVERY", style: AppTheme.labelUi(11, color: AppTheme.kTextSec)),
                const SizedBox(height: 6),
                Text(
                  "If the robot cannot reach your router or network changed, reset it to Hotspot mode. You can also hold Button 1 on the robot hardware for 4 seconds.",
                  style: AppTheme.labelUi(10, color: AppTheme.kTextSec),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _confirmResetToHotspot,
                  child: ClippedCornerBox(
                    cutSize: 5,
                    backgroundColor: AppTheme.kStop.withValues(alpha: 0.12),
                    borderColor: AppTheme.kStop,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.settings_backup_restore_rounded, color: AppTheme.kStop, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            "RESET ROBOT TO HOTSPOT (192.168.4.1)",
                            style: AppTheme.labelUi(11, color: AppTheme.kStop, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
