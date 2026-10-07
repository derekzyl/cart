package com.example.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var pendingResult: MethodChannel.Result? = null
    private var apWatch: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cart/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindWifi" -> bindToWifi(call.argument<String>("host"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindToWifi(host: String?, result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        // Drop whatever the process was bound to. After the robot reboots that
        // object is dead, and Android keeps using it until the app is killed.
        cm.bindProcessToNetwork(null)
        watchAp(cm, host)
        val already = wifiNetworkAlreadyUp(cm, host)
        if (already != null) {
            result.success(cm.bindProcessToNetwork(already))
            return
        }

        pendingResult?.success(false)
        pendingResult = result

        networkCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val bound = cm.bindProcessToNetwork(network)
                finish(bound)
            }

            override fun onUnavailable() {
                finish(false)
            }
        }
        networkCallback = callback
        cm.requestNetwork(request, callback, mainHandler, 1500)
    }

    private fun wifiNetworkAlreadyUp(cm: ConnectivityManager, host: String?): Network? {
        val wantAp = host?.startsWith("192.168.4.") == true
        var fallback: Network? = null
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            if (Build.VERSION.SDK_INT >= 28 &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
            ) {
                continue
            }
            val links: LinkProperties = cm.getLinkProperties(network) ?: continue
            val onAp = links.linkAddresses.any { addr ->
                addr.address.hostAddress?.startsWith("192.168.4.") == true
            }
            if (wantAp && onAp) return network
            if (!wantAp && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                return network
            }
            if (!wantAp && fallback == null) fallback = network
        }
        // Robot hotspot: do not bind some other Wi-Fi. Caller drops the dead
        // bind and waits for 192.168.4.x to come back.
        return if (wantAp) null else fallback
    }

    private fun watchAp(cm: ConnectivityManager, host: String?) {
        if (apWatch != null || host?.startsWith("192.168.4.") != true) return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val links = cm.getLinkProperties(network) ?: return
                val onAp = links.linkAddresses.any { addr ->
                    addr.address.hostAddress?.startsWith("192.168.4.") == true
                }
                if (onAp) cm.bindProcessToNetwork(network)
            }

            override fun onLost(network: Network) {
                cm.bindProcessToNetwork(null)
            }
        }
        apWatch = callback
        cm.requestNetwork(request, callback)
    }

    private fun finish(ok: Boolean) {
        mainHandler.post {
            pendingResult?.success(ok)
            pendingResult = null
        }
    }
}
