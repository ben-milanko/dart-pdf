package dev.milanko.dart_pdf_editor_app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Forwards PDFs the OS opens in the app - a Files "open", a download tap, or a
/// share - to the Dart `IncomingFileService` over a single method channel.
class MainActivity : FlutterActivity() {
    private val channelName = "dev.milanko.dartpdf/incoming"
    private val imageClipboardChannelName = "dev.milanko.dartpdf/image_clipboard"
    private val nativePrintChannelName = "dev.milanko.dartpdf/native_print"
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageClipboardChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "copyPng" -> {
                            val bytes = call.arguments as? ByteArray
                            if (bytes == null) {
                                result.error("bad_args", "copyPng expects PNG bytes", null)
                                return@setMethodCallHandler
                            }
                            result.success(copyPngToClipboard(bytes))
                        }
                        "readImage" -> result.success(readImageFromClipboard())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("clipboard_error", e.message, null)
                }
            }
        // Print without a bundled PDF engine: the Dart side hands over the whole
        // PDF and Android's own print framework renders its vector content,
        // keeping text selectable.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativePrintChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printPdf" -> {
                        val pdf = call.argument<ByteArray>("pdf")
                        if (pdf == null) {
                            result.error("bad_args", "printPdf expects pdf bytes", null)
                        } else {
                            result.success(printPdf(pdf, call.argument<String>("name") ?: "Document"))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        channel = ch
        handleIntent(intent, initial = true)
    }

    /// Hands the whole PDF to Android's print framework, which renders it.
    /// Returns false when the print service is unavailable.
    private fun printPdf(pdf: ByteArray, name: String): Boolean {
        val printManager =
            getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return false
        printManager.print(
            name,
            PdfBytesPrintAdapter(pdf, name),
            PrintAttributes.Builder().build()
        )
        return true
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

    private fun copyPngToClipboard(bytes: ByteArray): Boolean {
        val dir = File(cacheDir, "clipboard")
        dir.mkdirs()
        File(dir, ImageClipboardProvider.snapshotName).writeBytes(bytes)

        val uri = Uri.parse(
            "content://${applicationContext.packageName}.image_clipboard/" +
                ImageClipboardProvider.snapshotName
        )
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newUri(contentResolver, "Snapshot", uri))
        return true
    }

    private fun readImageFromClipboard(): ByteArray? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return null
        val description = clip.description
        for (i in 0 until clip.itemCount) {
            val uri = clip.getItemAt(i).uri ?: continue
            val type = contentResolver.getType(uri)
            val looksLikeImage =
                type?.startsWith("image/") == true || description.hasMimeType("image/*")
            if (!looksLikeImage) continue
            return contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }
        return null
    }
}

/// A PrintDocumentAdapter that streams the document's own PDF bytes straight to
/// Android's print spooler, which renders the vector content itself - no
/// re-rendering, no bundled PDF engine.
private class PdfBytesPrintAdapter(
    private val pdf: ByteArray,
    private val jobName: String
) : PrintDocumentAdapter() {
    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        // The page count is unknown without parsing the PDF; the framework
        // accepts PAGE_COUNT_UNKNOWN and discovers it while rendering.
        val info = PrintDocumentInfo.Builder("$jobName.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .build()
        callback.onLayoutFinished(info, true)
    }

    override fun onWrite(
        pageRanges: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback
    ) {
        try {
            FileOutputStream(destination.fileDescriptor).use { it.write(pdf) }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: Exception) {
            callback.onWriteFailed(e.message)
        }
    }
}
