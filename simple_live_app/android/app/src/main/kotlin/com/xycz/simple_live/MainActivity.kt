package com.xycz.simple_live

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Proxy
import android.os.Build

class MainActivity: FlutterActivity() {
    private var networkChannel: MethodChannel? = null
    private var proxyReceiverRegistered = false
    private val proxyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            networkChannel?.invokeMethod("proxyChanged", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        networkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simple_live/network")
        networkChannel?.setMethodCallHandler { call, result ->
            if (call.method != "getSystemProxy") {
                result.notImplemented()
            } else {
                try {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val proxy = manager.defaultProxy
                    result.success(if (proxy == null) null else mapOf(
                        "host" to proxy.host,
                        "port" to proxy.port,
                        "exclusions" to proxy.exclusionList.toList()
                    ))
                } catch (error: Exception) {
                    result.error("SYSTEM_PROXY", "Could not read system HTTP proxy", null)
                }
            }
        }
        val filter = IntentFilter(Proxy.PROXY_CHANGE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(proxyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(proxyReceiver, filter)
        }
        proxyReceiverRegistered = true
    }

    override fun onDestroy() {
        if (proxyReceiverRegistered) unregisterReceiver(proxyReceiver)
        networkChannel?.setMethodCallHandler(null)
        networkChannel = null
        super.onDestroy()
    }
}
