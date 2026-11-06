package com.mindpocket.mindpocket

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "mindpocket/screenshots"
    private val io = Executors.newSingleThreadExecutor()
    private val permissionRequestCode = 4701
    private val pendingPermissions = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permission" -> result.success(hasImagePermission())
                    "requestPermission" -> requestImagePermission(result)
                    "count" -> onWorker(result, "query_failed") { countScreenshots() }
                    "list" -> {
                        val afterId = call.argument<String>("afterId")
                        val limit = (call.argument<Number>("limit"))?.toInt() ?: 500
                        onWorker(result, "query_failed") {
                            require(limit in 1..500) { "limit must be between 1 and 500" }
                            queryScreenshots(afterId, limit)
                        }
                    }
                    "copy" -> {
                        val contentUri = call.argument<String>("contentUri")
                        val destination = call.argument<String>("destination")
                        if (contentUri.isNullOrBlank() || destination.isNullOrBlank()) {
                            result.error("bad_args", "contentUri and destination are required", null)
                        } else {
                            onWorker(result, "copy_failed") {
                                val uri = Uri.parse(contentUri)
                                require(uri.scheme == "content" && uri.authority == "media") {
                                    "A MediaStore content URI is required"
                                }
                                val input = contentResolver.openInputStream(uri)
                                    ?: throw IOException("The screenshot is no longer readable")
                                input.use {
                                    File(destination).outputStream().use { output ->
                                        it.copyTo(output, 64 * 1024)
                                    }
                                }
                                true
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Enumeration, metadata mapping and byte copies never occupy the UI thread. */
    private fun onWorker(result: MethodChannel.Result, code: String, work: () -> Any) {
        io.execute {
            val value = runCatching(work)
            runOnUiThread {
                value.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error(code, it.message, null) },
                )
            }
        }
    }

    private fun requestImagePermission(result: MethodChannel.Result) {
        if (hasImagePermission()) {
            result.success(true)
            return
        }
        pendingPermissions.add(result)
        if (pendingPermissions.size > 1) return
        val permissions = if (Build.VERSION.SDK_INT >= 34) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        } else {
            arrayOf(permissionName())
        }
        ActivityCompat.requestPermissions(this, permissions, permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = hasImagePermission()
        val requests = pendingPermissions.toList()
        pendingPermissions.clear()
        requests.forEach { it.success(granted) }
    }

    override fun onDestroy() {
        pendingPermissions.forEach {
            it.error("permission_interrupted", "The permission request was interrupted", null)
        }
        pendingPermissions.clear()
        io.shutdown()
        super.onDestroy()
    }

    private fun permissionName(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun hasImagePermission(): Boolean =
        ContextCompat.checkSelfPermission(this, permissionName()) == PackageManager.PERMISSION_GRANTED ||
            (Build.VERSION.SDK_INT >= 34 &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ==
                PackageManager.PERMISSION_GRANTED)

    private fun collection(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    private fun screenshotFilter(): String =
        "(${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} COLLATE NOCASE IN (?, ?, ?, ?) OR " +
            "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?)"

    private fun screenshotArguments(): Array<String> =
        arrayOf("Screenshots", "Screenshot", "Screen shots", "Screenshots ", "Screenshot%")

    private fun countScreenshots(): Int {
        check(hasImagePermission()) { "Screenshot access was not granted" }
        return contentResolver.query(
            collection(),
            arrayOf(MediaStore.Images.Media._ID),
            screenshotFilter(),
            screenshotArguments(),
            null,
        )?.use { it.count } ?: throw IOException("MediaStore did not return a cursor")
    }

    /** Stable ID keyset pagination cannot skip screenshots with equal dates. */
    private fun queryScreenshots(afterId: String?, limit: Int): List<Map<String, Any?>> {
        check(hasImagePermission()) { "Screenshot access was not granted" }
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
        )
        val args = screenshotArguments().toMutableList()
        val filter = if (afterId == null) {
            screenshotFilter()
        } else {
            val cursor = afterId.toLongOrNull()
            require(cursor != null && cursor >= 0) { "afterId is not a media ID" }
            args.add(cursor.toString())
            "${screenshotFilter()} AND ${MediaStore.Images.Media._ID} > ?"
        }
        val collection = collection()
        val rows = ArrayList<Map<String, Any?>>(limit)
        val cursor = contentResolver.query(
            collection,
            projection,
            filter,
            args.toTypedArray(),
            "${MediaStore.Images.Media._ID} ASC",
        ) ?: throw IOException("MediaStore did not return a cursor")
        cursor.use {
            val idCol = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val addedCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val takenCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val widthCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val sizeCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val bucketCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val mimeCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
            while (rows.size < limit && it.moveToNext()) {
                val id = it.getLong(idCol)
                val addedMillis = it.getLong(addedCol) * 1000L
                val taken = if (it.isNull(takenCol)) 0L else it.getLong(takenCol)
                rows.add(mapOf(
                    "id" to id.toString(),
                    "name" to (it.getString(nameCol) ?: ""),
                    "contentUri" to ContentUris.withAppendedId(collection, id).toString(),
                    "takenAt" to (if (taken > 0) taken else addedMillis),
                    "width" to it.getInt(widthCol),
                    "height" to it.getInt(heightCol),
                    "size" to it.getLong(sizeCol),
                    "bucket" to (it.getString(bucketCol) ?: "Screenshots"),
                    "mimeType" to (it.getString(mimeCol) ?: "image/png"),
                ))
            }
        }
        return rows
    }
}
