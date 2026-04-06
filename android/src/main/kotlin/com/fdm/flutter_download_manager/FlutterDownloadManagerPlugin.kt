package com.fdm.flutter_download_manager

import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class FlutterDownloadManagerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: android.content.Context

    companion object {
        private const val TAG = "FlutterDownloadManager"
    }

    private fun log(message: String) = Log.d(TAG, message)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "download_channel")
        channel.setMethodCallHandler(this)
        log("Plugin attached to engine")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        log("onMethodCall → method=${call.method}")

        when (call.method) {
            "saveToDownloads" -> {
                val filePath = call.argument<String>("filePath")
                    ?: return result.error("INVALID_ARG", "filePath is required", null)

                val fileName = call.argument<String>("fileName")
                    ?: return result.error("INVALID_ARG", "fileName is required", null)

                val subFolder = call.argument<String>("subFolder")
                val mimeType  = call.argument<String>("mimeType") ?: getMimeType(fileName)

                val relativePath = if (!subFolder.isNullOrBlank())
                    "${Environment.DIRECTORY_DOWNLOADS}/$subFolder"
                else
                    Environment.DIRECTORY_DOWNLOADS

                log("saveToDownloads → file=$fileName, relativePath=$relativePath")

                try {
                    val resolver = context.contentResolver

                    val contentValues = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    }

                    val uri = resolver.insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        contentValues
                    ) ?: return result.error("INSERT_FAILED", "MediaStore insert failed", null)

                    resolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(File(filePath)).use { input ->
                            input.copyTo(out)
                        }
                    } ?: return result.error("STREAM_FAILED", "Output stream failed", null)

                    // ✅ ALWAYS return String (IMPORTANT)
                    result.success(uri.toString())

                } catch (e: Exception) {
                    log("ERROR → ${e.message}")
                    result.error("SAVE_ERROR", e.message, null)
                }
            }

            else -> {
                log("Method not implemented → ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun resolveRealPath(uri: Uri): String? {
        val projection = arrayOf(MediaStore.MediaColumns.DATA)
        context.contentResolver.query(uri, projection, null, null, null)?.use {
            if (it.moveToFirst()) {
                val col = it.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (col != -1) return it.getString(col)
            }
        }
        return null
    }

    private fun findExistingFile(fileName: String, relativePath: String): Uri? {
        val resolver   = context.contentResolver
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection  =
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                    "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val args = arrayOf(fileName, "$relativePath/")

        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection, selection, args, null
        )?.use {
            if (it.moveToFirst()) {
                val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, id
                )
            }
        }
        return null
    }

    private fun getMimeType(fileName: String): String =
        when (fileName.substringAfterLast('.', "").lowercase()) {
            "pdf"  -> "application/pdf"
            "jpg", "jpeg" -> "image/jpeg"
            "png"  -> "image/png"
            "gif"  -> "image/gif"
            "webp" -> "image/webp"
            "mp4"  -> "video/mp4"
            "mkv"  -> "video/x-matroska"
            "avi"  -> "video/x-msvideo"
            "mp3"  -> "audio/mpeg"
            "wav"  -> "audio/wav"
            "aac"  -> "audio/aac"
            "zip"  -> "application/zip"
            "rar"  -> "application/x-rar-compressed"
            "apk"  -> "application/vnd.android.package-archive"
            "doc"  -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls"  -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt"  -> "application/vnd.ms-powerpoint"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "txt"  -> "text/plain"
            else   -> "application/octet-stream"
        }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        log("Plugin detached from engine")
    }
}