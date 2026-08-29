package com.example.warimesh

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var llmBridge: LlmBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = LlmBridge(applicationContext)
        llmBridge = bridge
        bridge.register(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LlmBridge.METHOD_CHANNEL),
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, LlmBridge.EVENT_CHANNEL),
        )
    }

    override fun onDestroy() {
        llmBridge?.dispose()
        llmBridge = null
        super.onDestroy()
    }
}
