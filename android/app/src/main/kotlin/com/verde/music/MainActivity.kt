package com.verde.music

import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.verde.music/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveAudio") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("BAD_ARGS", "Не переданы параметры файла.", null)
                    return@setMethodCallHandler
                }

                val filePath = args["filePath"] as? String
                val rawName = args["displayName"] as? String
                val title = (args["title"] as? String).orEmpty()
                val artist = (args["artist"] as? String).orEmpty()
                val mimeType = (args["mimeType"] as? String)
                    ?.takeIf { it.isNotBlank() } ?: "audio/mpeg"

                if (filePath.isNullOrBlank() || rawName.isNullOrBlank()) {
                    result.error(
                        "BAD_ARGS",
                        "Нужны путь к файлу и имя файла.",
                        null,
                    )
                    return@setMethodCallHandler
                }

                val source = File(filePath)
                if (!source.isFile) {
                    result.error(
                        "FILE_NOT_FOUND",
                        "Скачанный файл не найден.",
                        null,
                    )
                    return@setMethodCallHandler
                }

                // Не позволяем имени выйти за пределы Music/Verde.
                val displayName = File(rawName).name.ifBlank {
                    "Verde track.mp3"
                }

                try {
                    val savedPath = if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    ) {
                        saveWithMediaStore(
                            source,
                            displayName,
                            title,
                            artist,
                            mimeType,
                        )
                    } else {
                        saveLegacy(source, displayName, mimeType)
                    }
                    result.success(savedPath)
                } catch (error: SecurityException) {
                    result.error(
                        "PERMISSION_DENIED",
                        error.message ?: "Нет разрешения на запись в Music.",
                        null,
                    )
                } catch (error: Exception) {
                    result.error(
                        "SAVE_FAILED",
                        error.message ?: "Не удалось сохранить файл.",
                        null,
                    )
                }
            }
    }

    /**
     * Android 10+: системный MediaStore, без разрешений на хранилище.
     * IS_PENDING скрывает недописанный файл от плееров и галереи.
     */
    private fun saveWithMediaStore(
        source: File,
        displayName: String,
        title: String,
        artist: String,
        mimeType: String,
    ): String {
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Audio.Media.TITLE, title)
            put(MediaStore.Audio.Media.ARTIST, artist)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(
                MediaStore.Audio.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_MUSIC}/Verde",
            )
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val collection = MediaStore.Audio.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("MediaStore не принял файл.")

        try {
            val output = contentResolver.openOutputStream(uri)
                ?: throw IOException("Не удалось открыть файл в MediaStore.")
            output.use { target ->
                source.inputStream().use { input -> input.copyTo(target) }
            }

            val finish = ContentValues().apply {
                put(MediaStore.Audio.Media.IS_PENDING, 0)
            }
            contentResolver.update(uri, finish, null, null)
        } catch (error: Exception) {
            // Не оставляем «битую» запись в медиатеке.
            contentResolver.delete(uri, null, null)
            throw error
        }

        val actualName = contentResolver.query(
            uri,
            arrayOf(MediaStore.Audio.Media.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: displayName

        return "Music/Verde/$actualName"
    }

    /**
     * Android 8–9: публичная папка Music/Verde напрямую.
     * Требуется WRITE_EXTERNAL_STORAGE (см. AndroidManifest).
     */
    @Suppress("DEPRECATION")
    private fun saveLegacy(
        source: File,
        displayName: String,
        mimeType: String,
    ): String {
        if (
            checkSelfPermission(
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Нет разрешения на запись в Music.")
        }

        val directory = File(
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_MUSIC,
            ),
            "Verde",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("Не удалось создать папку Music/Verde.")
        }

        val target = uniqueFile(directory, displayName)
        source.copyTo(target, overwrite = false)
        MediaScannerConnection.scanFile(
            this,
            arrayOf(target.absolutePath),
            arrayOf(mimeType),
            null,
        )

        return "Music/Verde/${target.name}"
    }

    private fun uniqueFile(directory: File, displayName: String): File {
        val extension = displayName.substringAfterLast('.', "")
        val base = if (extension.isEmpty()) {
            displayName
        } else {
            displayName.substringBeforeLast('.')
        }

        var candidate = File(directory, displayName)
        var counter = 2
        while (candidate.exists()) {
            val name = if (extension.isEmpty()) {
                "$base ($counter)"
            } else {
                "$base ($counter).$extension"
            }
            candidate = File(directory, name)
            counter++
        }
        return candidate
    }
}
