package app.eyecue.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts app-local model import and user-selected document export channels.
 *
 * Deliberately not a plugin: the flow is a single SAF pick and a bounded copy,
 * so there is no dependency to add and no plugin sync to keep. The chosen
 * document is copied into the app cache — the researcher's original file is
 * never modified, and no storage permission is requested. Dart-side validation
 * remains the compatibility gate.
 */
class MainActivity : FlutterActivity() {
    // Flutter 3.44 can hit an uninitialized semantics transform during
    // TalkBack exploration (flutter/flutter#184810). Drop only that hover.
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        return try {
            super.dispatchGenericMotionEvent(event)
        } catch (error: NullPointerException) {
            val hover = event.actionMasked == MotionEvent.ACTION_HOVER_ENTER ||
                event.actionMasked == MotionEvent.ACTION_HOVER_MOVE ||
                event.actionMasked == MotionEvent.ACTION_HOVER_EXIT
            val matrixFailure = error.stackTrace.any {
                it.className == "android.opengl.Matrix" && it.methodName == "invertM"
            }
            val flutterView = error.stackTrace.any { it.className.startsWith("io.flutter.view.") }
            if (!hover || !matrixFailure || !flutterView) throw error
            Log.w("EyeCueAccessibility", "Ignored Flutter accessibility hover with an uninitialized transform")
            true
        }
    }

    private var pendingPick: MethodChannel.Result? = null
    private data class ExportRequest(val result: MethodChannel.Result, val source: File)
    private var pendingExport: ExportRequest? = null
    private val exportExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTflite" -> pick(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveDocument") {
                    saveDocument(
                        call.argument<String>("sourcePath"),
                        call.argument<String>("fileName"),
                        call.argument<String>("mimeType"),
                        result,
                    )
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun saveDocument(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        if (pendingPick != null || pendingExport != null) {
            result.error("busy", "A document picker or export is already open.", null)
            return
        }
        val source = try {
            sourcePath?.let { File(it).canonicalFile }
        } catch (e: Exception) {
            null
        }
        if (source == null || !source.isFile || !source.canRead() ||
            !source.path.startsWith(cacheDir.canonicalPath + File.separator) ||
            fileName.isNullOrBlank() || fileName != File(fileName).name ||
            mimeType !in setOf("application/json", "text/csv")
        ) {
            result.error("invalid_export", "The staged export cannot be read.", null)
            return
        }
        pendingExport = ExportRequest(result, source)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            startActivityForResult(intent, REQUEST_EXPORT)
        } catch (e: Exception) {
            pendingExport = null
            result.error("no_picker", "No document destination picker is available.", null)
        }
    }

    private fun finishExport(resultCode: Int, uri: Uri?) {
        val request = pendingExport ?: return
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingExport = null
            request.result.success(null)
            return
        }
        // Keep the pending slot occupied until the provider stream is closed.
        // File data never crosses the platform channel or blocks the UI thread.
        exportExecutor.execute {
            val error = try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw java.io.IOException("No writable document stream")
                output.use { target ->
                    request.source.inputStream().use { source -> source.copyTo(target) }
                    target.flush()
                }
                null
            } catch (e: Exception) {
                "write_failed"
            }
            val displayName = if (error == null) runCatching {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            }.getOrNull() else null
            runOnUiThread {
                if (pendingExport === request) {
                    pendingExport = null
                    if (error == null) {
                        request.result.success(displayName?.takeIf { it.isNotBlank() }
                            ?: request.source.name)
                    } else {
                        // Never delete a selected document on failure: it might
                        // be an existing file. The app's trial is also untouched.
                        request.result.error("write_failed",
                            "The chosen location could not finish saving the export.", null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        pendingExport?.result?.error("activity_closed", "The export activity closed.", null)
        pendingExport = null
        pendingPick?.error("activity_closed", "The model picker activity closed.", null)
        pendingPick = null
        exportExecutor.shutdown()
        super.onDestroy()
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null || pendingExport != null) {
            result.error("busy", "A model picker is already open.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Providers report .tflite inconsistently; keep octet-stream as the
            // primary type and allow anything so the file stays selectable.
            type = "application/octet-stream"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/octet-stream", "*/*"),
            )
        }
        try {
            startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error(
                "no_picker",
                "No document picker is available on this device.",
                null,
            )
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (requestCode == REQUEST_EXPORT) {
            finishExport(resultCode, data?.data)
            return
        }
        if (requestCode != REQUEST_PICK) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val target = File(
            cacheDir,
            "model-import-${System.currentTimeMillis()}.tflite",
        )
        val error = try {
            copyToCache(uri, target)
        } catch (e: Exception) {
            "unreadable"
        }
        when (error) {
            null -> result.success(target.absolutePath)
            "too_large" -> {
                target.delete()
                result.error(
                    "too_large",
                    "The selected model is larger than 40 MB.",
                    null,
                )
            }
            else -> {
                target.delete()
                result.error(
                    "unreadable",
                    "The selected file could not be read.",
                    null,
                )
            }
        }
    }

    /** Copies [uri] into [target]; returns null on success, else an error code. */
    private fun copyToCache(uri: Uri, target: File): String? {
        val input = contentResolver.openInputStream(uri) ?: return "unreadable"
        input.use { source ->
            target.outputStream().use { sink ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val read = source.read(buffer)
                    if (read <= 0) break
                    total += read
                    if (total > MAX_BYTES) return "too_large"
                    sink.write(buffer, 0, read)
                }
                sink.flush()
            }
        }
        return if (target.length() > 0) null else "unreadable"
    }

    private companion object {
        const val CHANNEL = "eyecue/model_picker"
        const val EXPORT_CHANNEL = "eyecue/document_export"
        const val REQUEST_EXPORT = 0x4558
        const val REQUEST_PICK = 0x4D4F4445 // "MODE"
        const val MAX_BYTES = 40L * 1024 * 1024
    }
}
