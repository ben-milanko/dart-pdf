package dev.milanko.dart_pdf_editor_app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
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

    /// Pages accumulated for the current native print job (JPEG bytes) and its
    /// title. Printing renders with our own engine and spools through the
    /// Android print framework, never a bundled PDF engine.
    private var printPages: MutableList<ByteArray> = mutableListOf()
    private var printJobTitle: String = "Document"

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
        // Print without a bundled PDF engine: the Dart side renders each page
        // and streams it here as a JPEG; endJob spools them through Android's
        // own PrintManager (drawing into the framework's PdfDocument).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativePrintChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "beginJob" -> {
                        printPages = mutableListOf()
                        printJobTitle = call.argument<String>("name") ?: "Document"
                        result.success(mapOf("dpi" to 300))
                    }
                    "printPage" -> {
                        val bytes = call.argument<ByteArray>("image")
                        if (bytes == null) {
                            result.error("bad_args", "printPage expects image bytes", null)
                        } else {
                            printPages.add(bytes)
                            result.success(true)
                        }
                    }
                    "endJob" -> result.success(startPrintJob())
                    "cancelJob" -> {
                        printPages = mutableListOf()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        channel = ch
        handleIntent(intent, initial = true)
    }

    /// Submits the accumulated page images to Android's print framework.
    /// Returns false when there is nothing to print or the service is missing.
    private fun startPrintJob(): Boolean {
        val pages = printPages.toList()
        printPages = mutableListOf()
        if (pages.isEmpty()) return false
        val printManager =
            getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return false
        printManager.print(
            printJobTitle,
            ImagePrintAdapter(pages, printJobTitle),
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

/// A PrintDocumentAdapter that paints one image per page into a framework
/// [PdfDocument] (the OS's own PDF writer, not a bundled PDFium) and hands it to
/// Android's print spooler. Each image is aspect-fitted and centred on the
/// sheet at the print job's chosen media size.
private class ImagePrintAdapter(
    private val pages: List<ByteArray>,
    private val jobName: String
) : PrintDocumentAdapter() {
    private var attributes: PrintAttributes? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?
    ) {
        attributes = newAttributes
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        val info = PrintDocumentInfo.Builder("$jobName.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(pages.size)
            .build()
        callback.onLayoutFinished(info, oldAttributes != newAttributes)
    }

    override fun onWrite(
        pageRanges: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback
    ) {
        // Media size is in mils (1/1000 in); PdfDocument pages are in points
        // (1/72 in). The high-resolution bitmap is drawn into the point-sized
        // page, so the printer keeps the raster's detail.
        val mediaSize = attributes?.mediaSize ?: PrintAttributes.MediaSize.ISO_A4
        val widthPts = (mediaSize.widthMils / 1000.0 * 72).toInt().coerceAtLeast(1)
        val heightPts = (mediaSize.heightMils / 1000.0 * 72).toInt().coerceAtLeast(1)

        val pdf = PdfDocument()
        try {
            for ((index, bytes) in pages.withIndex()) {
                if (cancellationSignal?.isCanceled == true) {
                    callback.onWriteCancelled()
                    return
                }
                val pageInfo = PdfDocument.PageInfo
                    .Builder(widthPts, heightPts, index + 1)
                    .create()
                val page = pdf.startPage(pageInfo)
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap != null) {
                    page.canvas.drawBitmap(
                        bitmap, null,
                        aspectFit(bitmap.width, bitmap.height, widthPts, heightPts),
                        null
                    )
                    bitmap.recycle()
                }
                pdf.finishPage(page)
            }
            FileOutputStream(destination.fileDescriptor).use { pdf.writeTo(it) }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: Exception) {
            callback.onWriteFailed(e.message)
        } finally {
            pdf.close()
        }
    }

    private fun aspectFit(iw: Int, ih: Int, pw: Int, ph: Int): Rect {
        if (iw <= 0 || ih <= 0) return Rect(0, 0, pw, ph)
        val scale = minOf(pw.toFloat() / iw, ph.toFloat() / ih)
        val w = (iw * scale).toInt()
        val h = (ih * scale).toInt()
        val left = (pw - w) / 2
        val top = (ph - h) / 2
        return Rect(left, top, left + w, top + h)
    }
}
