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

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "dev.milanko.dart_pdf_printing")
        channel?.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "printPdf") { result.notImplemented(); return }
        val pdf = call.argument<ByteArray>("pdf")
        if (pdf == null) { result.error("bad_args", "printPdf expects pdf bytes", null); return }
        if (activity == null) { result.error("no_activity", "Printing requires an attached Activity", null); return }
        try {
            result.success(printPdf(pdf, call.argument<String>("name") ?: "Document",
                call.argument<Boolean>("useDocumentPageSize") == true,
                call.argument<Number>("pageWidth")?.toDouble(),
                call.argument<Number>("pageHeight")?.toDouble()))
        } catch (error: Exception) {
            result.error("native_print_failed", error.message, null)
        }
    }

    /// Hands the whole PDF to Android's print framework, which renders it.
    /// Returns false when the print service is unavailable.
    private fun printPdf(
        pdf: ByteArray, name: String, useDocumentPageSize: Boolean = false,
        pageWidth: Double? = null, pageHeight: Double? = null
    ): Boolean {
        val printManager =
            activity?.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return false
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
        printManager.print(
            name,
            PdfBytesPrintAdapter(pdf, name),
            attributes.build()
        )
        return true
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
