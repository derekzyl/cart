package com.example.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cart/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindWifi" -> bindToWifi(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindToWifi(result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
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
        cm.requestNetwork(request, callback, mainHandler, 4000)
    }

    private fun finish(ok: Boolean) {
        mainHandler.post {
            pendingResult?.success(ok)
            pendingResult = null
        }
    }
}
