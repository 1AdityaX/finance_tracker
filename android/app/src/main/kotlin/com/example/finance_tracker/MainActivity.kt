package com.example.finance_tracker

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    /// The text to write once the user picks where to save it.
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the import screen pick a file with the system picker and read
        // it as text, and the export screen save text to a file the user
        // chooses. Both complete with null or false when nothing was picked.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openText" -> {
                        cancelPending()
                        pending = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                        startActivityForResult(intent, OPEN_TEXT)
                    }
                    "saveText" -> {
                        val name = call.argument<String>("name")
                        val mime = call.argument<String>("mime")
                        val text = call.argument<String>("text")
                        if (name == null || mime == null || text == null) {
                            return@setMethodCallHandler result.error("args", "name, mime and text are required", null)
                        }
                        cancelPending()
                        pending = result
                        pendingText = text
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(mime)
                            .putExtra(Intent.EXTRA_TITLE, name)
                        startActivityForResult(intent, SAVE_TEXT)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Completes a request still waiting on the picker as if nothing was picked.
    private fun cancelPending() {
        val result = pending ?: return
        val wasSave = pendingText != null
        pending = null
        pendingText = null
        result.success(if (wasSave) false else null)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN_TEXT && requestCode != SAVE_TEXT) return
        val result = pending ?: return
        val text = pendingText
        pending = null
        pendingText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            return result.success(if (requestCode == SAVE_TEXT) false else null)
        }
        try {
            if (requestCode == OPEN_TEXT) {
                val read = contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                result.success(read)
            } else {
                // "wt" truncates, so overwriting a longer file leaves no tail.
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: return result.error("write", "Couldn't open the file", null)
                stream.use { it.write((text ?: "").toByteArray(Charsets.UTF_8)) }
                result.success(true)
            }
        } catch (error: Exception) {
            result.error(if (requestCode == OPEN_TEXT) "read" else "write", error.message, null)
        }
    }

    private companion object {
        const val OPEN_TEXT = 4101
        const val SAVE_TEXT = 4102
    }
}
