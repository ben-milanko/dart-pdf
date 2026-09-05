package dev.milanko.dart_pdf_editor_app

import android.app.Activity
import android.app.ActivityManager
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
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.util.concurrent.Executors

/// Forwards PDFs the OS opens in the app - a Files "open", a download tap, or a
/// share - to the Dart `IncomingFileService` over a single method channel.
class MainActivity : FlutterActivity() {
    private val channelName = "dev.milanko.dartpdf/incoming"
    private val imageClipboardChannelName = "dev.milanko.dartpdf/image_clipboard"
    private val nativePrintChannelName = "dev.milanko.dartpdf/native_print"
    private val mobileFileChannelName = "dev.milanko.dartpdf/mobile_file"
    private val memoryChannelName = "dev.milanko.dartpdf/memory"
    private var channel: MethodChannel? = null

    /// The file the activity was launched with, drained by `getInitialFile`.
    private var pending: Map<String, Any>? = null

    /// Serializes the (potentially large) ranged FD reads off the platform
    /// thread so a multi-MB read can't ANR the UI.
    private val fileIoExecutor = Executors.newSingleThreadExecutor()

    /// The in-flight `pickDocuments` reply, held while the system document
    /// picker is up (its result arrives asynchronously in `onActivityResult`).
    private var pendingPick: MethodChannel.Result? = null
    private val openDocumentRequestCode = 0x0D_0C

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

        // Reference-based open (#364): a custom picker that keeps the original
        // content Uri instead of copying the whole file into the sandbox, plus
        // ranged reads over that Uri so a cloud pick can first-paint from a few
        // MB. See MobileFileByteSource on the Dart side.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mobileFileChannelName)
            .setMethodCallHandler { call, result -> handleMobileFile(call, result) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, memoryChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "snapshot") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val info = ActivityManager.MemoryInfo()
                manager.getMemoryInfo(info)
                result.success(
                    mapOf(
                        "physicalBytes" to info.totalMem,
                        "availableBytes" to info.availMem,
                        "processLimitBytes" to
                            manager.memoryClass.toLong() * 1024L * 1024L,
                        "lowMemory" to info.lowMemory,
                    )
                )
            }

        channel = ch
        handleIntent(intent, initial = true)
    }

    private fun handleMobileFile(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        when (call.method) {
            "pickDocuments" -> launchOpenDocument(result)
            "probeSeekable" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("bad_args", "probeSeekable expects a token", null)
                    return
                }
                fileIoExecutor.execute {
                    val seekable = probeSeekable(Uri.parse(token))
                    runOnUiThread { result.success(seekable) }
                }
            }
            "fileLength" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("bad_args", "fileLength expects a token", null)
                    return
                }
                fileIoExecutor.execute {
                    val len = fileLength(Uri.parse(token))
                    runOnUiThread { result.success(len) }
                }
            }
            "readRange" -> {
                val token = call.argument<String>("token")
                val offset = (call.argument<Number>("offset"))?.toLong()
                val length = call.argument<Int>("length")
                if (token == null || offset == null || length == null) {
                    result.error("bad_args", "readRange expects token/offset/length", null)
                    return
                }
                fileIoExecutor.execute {
                    try {
                        val bytes = readRange(Uri.parse(token), offset, length)
                        runOnUiThread { result.success(bytes) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("read_failed", e.message, null)
                        }
                    }
                }
            }
            "readUri" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("bad_args", "readUri expects a token", null)
                    return
                }
                fileIoExecutor.execute {
                    try {
                        val bytes = readWhole(Uri.parse(token))
                        runOnUiThread { result.success(bytes) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("read_failed", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /// Launches ACTION_OPEN_DOCUMENT so the returned Uri is a durable reference
    /// to the original file (persistable read permission) rather than a copy.
    private fun launchOpenDocument(result: MethodChannel.Result) {
        // Only one picker at a time; reject a second request rather than losing
        // the first reply.
        if (pendingPick != null) {
            result.error("busy", "A document picker is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            // Keep cloud providers (OneDrive/Drive/iCloud) in the list - the
            // whole point of #364 - so don't set EXTRA_LOCAL_ONLY.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingPick = result
        try {
            startActivityForResult(intent, openDocumentRequestCode)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != openDocumentRequestCode) return
        val reply = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            // Cancelled: an empty list means "user backed out", distinct from an
            // error.
            reply.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) }
        } else {
            data.data?.let { uris.add(it) }
        }
        fileIoExecutor.execute {
            val entries = uris.mapNotNull { describeOpenedDocument(it, data.flags) }
            runOnUiThread { reply.success(entries) }
        }
    }

    /// Persists read access to [uri], then builds the Dart-side descriptor
    /// (token/name/length/seekable). Returns null if access can't be persisted.
    private fun describeOpenedDocument(uri: Uri, intentFlags: Int): Map<String, Any?>? {
        return try {
            val persistable = intentFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (persistable != 0) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: SecurityException) {
                    // Provider doesn't grant persistable permission - the Uri is
                    // still usable for this session, which is all the first pick
                    // needs.
                }
            }
            mapOf(
                "token" to uri.toString(),
                "name" to (displayName(uri) ?: "document.pdf"),
                "length" to fileLength(uri),
                // The authority identifies the DocumentsProvider without
                // exposing the picked URI/path or its persisted access token.
                "provider" to (uri.authority ?: "android-documents-provider"),
                "seekable" to probeSeekable(uri),
            )
        } catch (e: Exception) {
            null
        }
    }

    /// True only when [uri] backs a real seekable file. Many cloud providers
    /// serve SAF a non-seekable pipe (statSize -1, lseek throws ESPIPE), where
    /// random access is impossible and the caller must stream whole instead.
    private fun probeSeekable(uri: Uri): Boolean {
        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                if (pfd.statSize < 0) return false
                val fd = pfd.fileDescriptor
                // Confirm random access end-to-end: seek forward and back.
                val probe = if (pfd.statSize > 1) 1L else 0L
                Os.lseek(fd, probe, OsConstants.SEEK_SET)
                Os.lseek(fd, 0, OsConstants.SEEK_SET)
                true
            } ?: false
        } catch (e: ErrnoException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    /// The file's length, or -1 when the provider doesn't report one (the Dart
    /// side treats -1 as "unknown" and falls back to a sequential read).
    private fun fileLength(uri: Uri): Long {
        try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                if (pfd.statSize >= 0) return pfd.statSize
            }
        } catch (_: Exception) {
        }
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.SIZE), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else -1L
            } ?: -1L
        } catch (_: Exception) {
            -1L
        }
    }

    /// Reads `[offset, offset+length)` from [uri] through a seekable FD. Only
    /// called after [probeSeekable] passed, so the FD supports lseek.
    private fun readRange(uri: Uri, offset: Long, length: Int): ByteArray {
        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
            val fd = pfd.fileDescriptor
            Os.lseek(fd, offset, OsConstants.SEEK_SET)
            // Do not close this stream - it wraps the pfd's fd, which `use`
            // closes; closing here would double-close the descriptor.
            val input = FileInputStream(fd)
            val buffer = ByteArray(length)
            var read = 0
            while (read < length) {
                val n = input.read(buffer, read, length - read)
                if (n < 0) break // short read at EOF
                read += n
            }
            return if (read == length) buffer else buffer.copyOf(read)
        }
        return ByteArray(0)
    }

    /// Reads [uri] whole through the ContentResolver, which resolves `content://`
    /// and `file://` alike. This is the read the document scanner needs: ML Kit
    /// hands back a Uri into its own scratch space, and which scheme it carries
    /// depends on the Play Services build, so the Dart side can't open it by
    /// path. Throws when the Uri can't be opened, so the caller sees the reason
    /// instead of an empty result.
    private fun readWhole(uri: Uri): ByteArray {
        return contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw FileNotFoundException("Cannot open $uri")
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
