package com.example.finance_tracker

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the import screen pick a file with the system picker and read
        // it as text. Completes with null when nothing was picked.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "openText") return@setMethodCallHandler result.notImplemented()
                pending?.success(null)
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                startActivityForResult(intent, OPEN_TEXT)
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN_TEXT) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return result.success(null)
        try {
            val text = contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            result.success(text)
        } catch (error: Exception) {
            result.error("read", error.message, null)
        }
    }

    private companion object {
        const val OPEN_TEXT = 4101
    }
}
