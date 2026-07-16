package dev.milanko.dart_pdf_editor_app

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

class ImageClipboardProvider : ContentProvider() {
    companion object {
        const val snapshotName = "snapshot.png"
    }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "image/png"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (!mode.contains("r")) {
            throw FileNotFoundException("Clipboard image is read-only")
        }
        val file = snapshotFile()
        if (!isSnapshotUri(uri) || file == null || !file.exists()) {
            throw FileNotFoundException("Clipboard image not found")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val file = snapshotFile()
        if (!isSnapshotUri(uri) || file == null || !file.exists()) return null
        val columns = projection ?: arrayOf(
            OpenableColumns.DISPLAY_NAME,
            OpenableColumns.SIZE,
        )
        val cursor = MatrixCursor(columns)
        val row = cursor.newRow()
        for (column in columns) {
            row.add(
                column,
                when (column) {
                    OpenableColumns.DISPLAY_NAME -> snapshotName
                    OpenableColumns.SIZE -> file.length()
                    else -> null
                }
            )
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    private fun snapshotFile(): File? {
        val context = context ?: return null
        return File(File(context.cacheDir, "clipboard"), snapshotName)
    }

    private fun isSnapshotUri(uri: Uri): Boolean = uri.lastPathSegment == snapshotName
}
