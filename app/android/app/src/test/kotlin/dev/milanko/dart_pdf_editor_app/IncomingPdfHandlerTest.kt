package dev.milanko.dart_pdf_editor_app

import android.content.*
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class IncomingPdfHandlerTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val uri = Uri.parse("content://pdf-fixture/opaque/42")
    private val bytes = "%PDF-1.7\nsynthetic incoming transport fixture\n%%EOF".toByteArray()
    private lateinit var provider: FixtureProvider

    @Before fun setup() {
        provider = Robolectric.buildContentProvider(FixtureProvider::class.java)
            .create("pdf-fixture").get()
        provider.file = File(context.cacheDir, "fixture.pdf").apply { writeBytes(bytes) }
    }

    private fun view(data: Uri? = uri) = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(data, "application/pdf")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    @Test fun pdfResolverAcceptsTypeOnlyContentAndFileButNotOtherTypesOrNetwork() {
        val pm = context.packageManager
        fun matches(intent: Intent) = pm.queryIntentActivities(intent,
            PackageManager.MATCH_DEFAULT_ONLY).any {
            it.activityInfo.name == "dev.milanko.dart_pdf_editor_app.MainActivity"
        }
        assertTrue(matches(view(null)))
        assertTrue(matches(view()))
        assertTrue(matches(view(Uri.parse("file:///storage/Download/test.pdf"))))
        assertFalse(matches(view(Uri.parse("https://example.invalid/test.pdf"))))
        assertFalse(matches(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "image/png")))
        assertTrue(matches(Intent(Intent.ACTION_SEND).setType("application/pdf")))
    }

    @Test fun coldOpenIsDrainedOnceAndWarmOpenDeliversBytesWithoutWritablePath() {
        val handler = IncomingPdfHandler()
        val delivered = mutableListOf<Map<String, Any>>()
        handler.handle(view(), true, context.contentResolver, delivered::add)
        assertTrue(delivered.isEmpty())
        val initial = handler.takeInitialFile()!!
        assertArrayEquals(bytes, initial["bytes"] as ByteArray)
        assertEquals("fixture.pdf", initial["name"])
        assertFalse(initial.containsKey("path"))
        assertNull(handler.takeInitialFile())
        handler.handle(view(), false, context.contentResolver, delivered::add)
        assertArrayEquals(bytes, delivered.single()["bytes"] as ByteArray)
        assertNull(handler.takeInitialFile())
    }

    @Test fun sendSupportsExtraStreamAndClipDataOnly() {
        for (useClip in listOf(false, true)) {
            val intent = Intent(Intent.ACTION_SEND).setType("application/pdf")
            if (useClip) intent.clipData = ClipData.newRawUri("PDF", uri)
            else intent.putExtra(Intent.EXTRA_STREAM, uri)
            val handler = IncomingPdfHandler()
            handler.handle(intent, true, context.contentResolver) { fail("cold open") }
            assertArrayEquals(bytes, handler.takeInitialFile()!!["bytes"] as ByteArray)
        }
    }

    @Test fun optionalMetadataCannotDiscardReadablePdf() {
        for (mode in listOf("throws", "missing", "empty")) {
            provider.metadata = mode
            val handler = IncomingPdfHandler()
            handler.handle(view(), true, context.contentResolver) { fail("cold open") }
            val result = handler.takeInitialFile()!!
            assertEquals("document.pdf", result["name"])
            assertArrayEquals(bytes, result["bytes"] as ByteArray)
        }
    }

    @Test fun deniedReadAndUnrelatedIntentsDoNotDeliverOrCrash() {
        provider.deny = true
        val handler = IncomingPdfHandler()
        handler.handle(view(), true, context.contentResolver) { fail("denied") }
        assertNull(handler.takeInitialFile())
        provider.deny = false
        handler.handle(Intent(Intent.ACTION_MAIN).setData(uri), false,
            context.contentResolver) { fail("launcher") }
        handler.handle(view(Uri.parse("https://example.invalid/test.pdf")), false,
            context.contentResolver) { fail("network") }
        handler.handle(view(null), false, context.contentResolver) { fail("no URI") }
    }

    @Test fun fileUriReadsThroughResolver() {
        val handler = IncomingPdfHandler()
        handler.handle(view(Uri.fromFile(provider.file)), true, context.contentResolver) {}
        assertArrayEquals(bytes, handler.takeInitialFile()!!["bytes"] as ByteArray)
    }
}

class FixtureProvider : ContentProvider() {
    lateinit var file: File
    var metadata = "name"
    var deny = false
    override fun onCreate() = true
    override fun getType(uri: Uri) = "application/pdf"
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (deny) throw SecurityException("Synthetic denied grant")
        check(mode == "r")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        if (metadata == "throws") throw SecurityException("Metadata unavailable")
        if (metadata == "missing") return MatrixCursor(arrayOf("other"))
        return MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply {
            if (metadata != "empty") addRow(arrayOf("fixture.pdf"))
        }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?,
        args: Array<out String>?) = 0
}
