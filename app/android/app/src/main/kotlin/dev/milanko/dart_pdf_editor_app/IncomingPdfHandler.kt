package dev.milanko.dart_pdf_editor_app

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns

/** Reads a granted URI, never a guessed filesystem path or a writable origin. */
internal class IncomingPdfHandler {
    private var pending: Map<String, Any>? = null

    fun takeInitialFile(): Map<String, Any>? = pending.also { pending = null }

    fun handle(
        intent: Intent?,
        initial: Boolean,
        resolver: ContentResolver,
        deliver: (Map<String, Any>) -> Unit,
    ) {
        val uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data ?: firstClipUri(intent)
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                stream ?: firstClipUri(intent)
            }
            else -> null
        } ?: return
        // Do not turn an externally supplied URI into a network request.
        if (uri.scheme != "content" && uri.scheme != "file") return
        val bytes = try {
            resolver.openInputStream(uri)?.use { it.readBytes() } ?: return
        } catch (_: Exception) {
            return
        }
        // DISPLAY_NAME is optional. A provider may supply readable bytes while
        // refusing metadata queries (or omit this column altogether).
        val name = try {
            if (uri.scheme == "file") uri.lastPathSegment else {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { cursor ->
                        val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
                    }
            }
        } catch (_: Exception) {
            null
        }
        val payload = mapOf("name" to (name?.takeIf { it.isNotBlank() } ?: "document.pdf"),
            "bytes" to bytes)
        // Copy during the temporary read grant; no persistable/storage permission
        // is required. Dart caches the bytes for recents and uses Save As.
        if (initial) pending = payload else deliver(payload)
    }

    private fun firstClipUri(intent: Intent): Uri? = intent.clipData?.let {
        if (it.itemCount > 0) it.getItemAt(0).uri else null
    }
}
