package dev.milanko.dart_pdf_editor_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Forwards PDFs the OS opens in the app — a Files "open", a download tap, or a
/// share — to the Dart `IncomingFileService` over a single method channel.
class MainActivity : FlutterActivity() {
    private val channelName = "dev.milanko.dartpdf/incoming"
    private var channel: MethodChannel? = null

    /// The file the activity was launched with, drained by `getInitialFile`.
    private var pending: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        handleIntent(intent, initial = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, initial = false)
    }

    private fun handleIntent(intent: Intent?, initial: Boolean) {
        val uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            else -> null
        } ?: return
        val payload = readPayload(uri) ?: return
        if (initial) {
            pending = payload
        } else {
            channel?.invokeMethod("openFile", payload)
        }
    }

    private fun readPayload(uri: Uri): Map<String, Any>? {
        return try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return null
            mapOf("name" to (displayName(uri) ?: "document.pdf"), "bytes" to bytes)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }
}
