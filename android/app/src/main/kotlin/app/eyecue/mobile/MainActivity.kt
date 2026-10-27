package app.eyecue.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the app-local model picker channel (`eyecue/model_picker`).
 *
 * Deliberately not a plugin: the flow is a single SAF pick and a bounded copy,
 * so there is no dependency to add and no plugin sync to keep. The chosen
 * document is copied into the app cache — the researcher's original file is
 * never modified, and no storage permission is requested. Dart-side validation
 * remains the compatibility gate.
 */
class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTflite" -> pick(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
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
        const val REQUEST_PICK = 0x4D4F4445 // "MODE"
        const val MAX_BYTES = 40L * 1024 * 1024
    }
}
