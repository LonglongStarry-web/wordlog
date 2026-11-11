package com.wenxu.wordlog

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "wordlog/native"
        const val PREFS = "wordlog_widget"
        const val KEY_PENDING = "pending_json"
        const val KEY_COUNT = "today_count"
        const val KEY_RECENT = "recent_words"
        const val REQ_PICK_DIR = 4242
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, REQ_PICK_DIR)
                    }

                    "writeFile" -> {
                        val uri = call.argument<String>("uri")
                        val fileName = call.argument<String>("fileName")
                        val content = call.argument<String>("content")
                        if (uri == null || fileName == null || content == null) {
                            result.success(false)
                        } else {
                            result.success(writeToTree(uri, fileName, content))
                        }
                    }

                    "readFile" -> {
                        val uri = call.argument<String>("uri")
                        val fileName = call.argument<String>("fileName")
                        if (uri == null || fileName == null) {
                            result.success(null)
                        } else {
                            result.success(readFromTree(uri, fileName))
                        }
                    }

                    "filesDir" -> result.success(filesDir.absolutePath)

                    "writeBytes" -> {
                        val uri = call.argument<String>("uri")
                        val rel = call.argument<String>("relativePath")
                        val bytes = asBytes(call.argument<Any>("bytes"))
                        if (uri == null || rel == null || bytes == null) {
                            result.success(false)
                        } else {
                            result.success(writeBytesToTree(uri, rel, bytes))
                        }
                    }

                    "getPending" -> result.success(readPending())

                    "clearPending" -> {
                        prefs().edit().putString(KEY_PENDING, "[]").apply()
                        result.success(true)
                    }

                    "setWidgetStats" -> {
                        val count = call.argument<Int>("count") ?: 0
                        val recent = call.argument<List<String>>("recent") ?: emptyList()
                        prefs().edit()
                            .putInt(KEY_COUNT, count)
                            .putString(KEY_RECENT, recent.joinToString("\n"))
                            .apply()
                        WidgetBridge.refresh(this)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_DIR) {
            val uri = data?.data
            if (uri != null && resultCode == Activity.RESULT_OK) {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                try {
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (e: Exception) {
                    // 某些 ROM 不授予持久化权限，忽略
                }
                pendingResult?.success(uri.toString())
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun readPending(): List<Map<String, Any?>> {
        val raw = prefs().getString(KEY_PENDING, "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            val out = mutableListOf<Map<String, Any?>>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "name" to o.optString("name", ""),
                        "context" to o.optString("context", ""),
                        "ts" to o.optLong("ts", System.currentTimeMillis())
                    )
                )
            }
            out
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun writeToTree(uriStr: String, fileName: String, content: String): Boolean {
        return try {
            val tree = Uri.parse(uriStr)
            val dir = DocumentFile.fromTreeUri(this, tree) ?: return false
            var file = dir.findFile(fileName)
            if (file == null || !file.exists()) {
                file = dir.createFile("text/markdown", fileName)
            }
            if (file == null) return false
            contentResolver.openOutputStream(file.uri, "w")?.use {
                it.write(content.toByteArray(Charsets.UTF_8))
                it.flush()
            } ?: return false
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Flutter 侧的 Uint8List 在 Android 可能解码成 ByteArray 或 ByteBuffer */
    private fun asBytes(v: Any?): ByteArray? = when (v) {
        is ByteArray -> v
        is java.nio.ByteBuffer -> {
            val out = ByteArray(v.remaining())
            v.get(out)
            out
        }
        is List<*> -> v.mapNotNull {
            when (it) {
                is Int -> it.toByte()
                is Long -> it.toByte()
                else -> null
            }
        }.toByteArray()
        else -> null
    }

    /** 在已授权目录下按相对路径写二进制文件，中间目录自动创建 */
    private fun writeBytesToTree(uriStr: String, relativePath: String, bytes: ByteArray): Boolean {
        return try {
            val tree = Uri.parse(uriStr)
            var dir = DocumentFile.fromTreeUri(this, tree) ?: return false
            val parts = relativePath.split('/').filter { it.isNotBlank() }
            if (parts.isEmpty()) return false
            for (i in 0 until parts.lastIndex) {
                val seg = parts[i]
                val next = dir.findFile(seg)
                dir = if (next != null && next.isDirectory) {
                    next
                } else {
                    dir.createDirectory(seg) ?: return false
                }
            }
            val name = parts.last()
            var file = dir.findFile(name)
            if (file == null || !file.exists()) {
                file = dir.createFile("image/jpeg", name) ?: return false
            }
            contentResolver.openOutputStream(file.uri, "w")?.use {
                it.write(bytes)
                it.flush()
            } ?: return false
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun readFromTree(uriStr: String, fileName: String): String? {
        return try {
            val tree = Uri.parse(uriStr)
            val dir = DocumentFile.fromTreeUri(this, tree) ?: return null
            val file = dir.findFile(fileName) ?: return null
            contentResolver.openInputStream(file.uri)?.use {
                it.readBytes().toString(Charsets.UTF_8)
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WidgetBridge.refresh(this)
    }
}
