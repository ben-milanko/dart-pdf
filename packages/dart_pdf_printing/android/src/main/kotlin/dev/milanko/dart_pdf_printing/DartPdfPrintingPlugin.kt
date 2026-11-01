package dev.milanko.dart_pdf_printing

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import kotlin.math.roundToInt

class DartPdfPrintingPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    // Settles the open print job's reply; run early if the activity goes away
    // before the print framework finishes the adapter.
    private var settlePrint: (() -> Unit)? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "dev.milanko.dart_pdf_printing")
        channel?.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        detachActivity()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { detachActivity() }
    override fun onDetachedFromActivityForConfigChanges() { detachActivity() }

    private fun detachActivity() {
        activity = null
        settlePrint?.invoke()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "printPdf") { result.notImplemented(); return }
        val pdf = call.argument<ByteArray>("pdf")
        if (pdf == null) { result.error("bad_args", "printPdf expects pdf bytes", null); return }
        if (activity == null) { result.error("no_activity", "Printing requires an attached Activity", null); return }
        val reply = OnceResult(result)
        try {
            printPdf(pdf, call.argument<String>("name") ?: "Document",
                call.argument<Boolean>("useDocumentPageSize") == true,
                call.argument<Number>("pageWidth")?.toDouble(),
                call.argument<Number>("pageHeight")?.toDouble(),
                reply)
        } catch (error: Exception) {
            reply.error("native_print_failed", error.message)
        }
    }

    /// Hands the whole PDF to Android's print framework, which renders it.
    /// Answers [reply] once the print UI closes: true when the job was queued,
    /// false when the user backed out of it.
    private fun printPdf(
        pdf: ByteArray, name: String, useDocumentPageSize: Boolean,
        pageWidth: Double?, pageHeight: Double?, reply: OnceResult
    ) {
        val printManager =
            activity?.getSystemService(Context.PRINT_SERVICE) as? PrintManager
        if (printManager == null) {
            reply.error("printing_unavailable", "The Android print service is unavailable")
            return
        }
        val attributes = PrintAttributes.Builder()
        if (useDocumentPageSize && pageWidth != null && pageHeight != null &&
            pageWidth.isFinite() && pageHeight.isFinite() &&
            pageWidth > 0 && pageHeight > 0) {
            // Android expresses media in thousandths of an inch. The adapter
            // writes the already composed PDF verbatim; these are defaults for
            // the print service, which still negotiates supported printer media.
            attributes.setMediaSize(PrintAttributes.MediaSize(
                "dartpdf-sheet", "Document sheet",
                (pageWidth * 1000 / 72).roundToInt().coerceAtLeast(1),
                (pageHeight * 1000 / 72).roundToInt().coerceAtLeast(1)
            ))
            attributes.setMinMargins(PrintAttributes.Margins.NO_MARGINS)
        }
        val adapter = PdfBytesPrintAdapter(pdf, name)
        val job = printManager.print(name, adapter, attributes.build())
        // The spooler settles the job's state - QUEUED once the user confirms,
        // CANCELED when they leave the print UI - before it finishes the
        // adapter, so onFinish reads the user's decision.
        val settle = {
            val state = job.info?.state ?: PrintJobInfo.STATE_CANCELED
            reply.success(state != PrintJobInfo.STATE_CANCELED &&
                state != PrintJobInfo.STATE_CREATED)
            settlePrint = null
        }
        settlePrint = settle
        adapter.onFinished = settle
    }

}

/// Replies to a method call at most once: the print framework's callbacks are
/// not guaranteed to arrive exactly once.
private class OnceResult(private val result: MethodChannel.Result) {
    private var answered = false
    fun success(value: Any?) {
        if (answered) return
        answered = true
        result.success(value)
    }
    fun error(code: String, message: String?) {
        if (answered) return
        answered = true
        result.error(code, message, null)
    }
}

/// A PrintDocumentAdapter that streams the document's own PDF bytes straight to
/// Android's print spooler, which renders the vector content itself - no
/// re-rendering, no bundled PDF engine.
private class PdfBytesPrintAdapter(
    private val pdf: ByteArray,
    private val jobName: String
) : PrintDocumentAdapter() {
    /// Called once the print UI is gone and the spooler is done with us.
    var onFinished: (() -> Unit)? = null

    override fun onFinish() {
        onFinished?.invoke()
        onFinished = null
    }

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
