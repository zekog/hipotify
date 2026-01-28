package com.example.hipotify

import android.util.Log
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.MediaScannerConnection
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.images.ArtworkFactory
import org.jaudiotagger.tag.reference.PictureTypes
import org.jaudiotagger.audio.flac.metadatablock.MetadataBlockDataPicture
import org.jaudiotagger.tag.flac.FlacTag
import android.graphics.BitmapFactory
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.hipotify/media_scanner"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.hipotify/audio").setMethodCallHandler { call, result ->
            if (call.method == "openAudioSession") {
                val sessionId = call.argument<Int>("sessionId")
                if (sessionId != null) {
                    sendAudioSessionBroadcast(sessionId)
                    result.success(null)
                } else {
                    result.error("INVALID_ID", "Session ID is null", null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, uri -> }
                        result.success(null)
                    } else {
                        result.error("INVALID_PATH", "Path cannot be null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.hipotify/metadata").setMethodCallHandler { call, result ->
            if (call.method == "tagFile") {
                val path = call.argument<String>("path")
                val title = call.argument<String>("title")
                val artist = call.argument<String>("artist")
                val album = call.argument<String>("album")
                val trackNumber = call.argument<Int>("trackNumber")
                val releaseDate = call.argument<String>("releaseDate")
                val coverPath = call.argument<String>("coverPath")

                Log.d("HipotifyMetadata", "Tagging file: $path")
                Log.d("HipotifyMetadata", "Title: $title, Artist: $artist, Album: $album")
                Log.d("HipotifyMetadata", "CoverPath: $coverPath")

                if (path != null) {
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            Log.e("HipotifyMetadata", "File does not exist: $path")
                            result.error("FILE_NOT_FOUND", "File not found", null)
                            return@setMethodCallHandler
                        }
                        
                        if (!file.canWrite()) {
                            Log.e("HipotifyMetadata", "File is not writable: $path")
                            // Try to make it writable
                            file.setWritable(true)
                            if (!file.canWrite()) {
                                Log.e("HipotifyMetadata", "Still cannot write to file: $path")
                            }
                        }

                        Log.d("HipotifyMetadata", "Reading audio file: $path")
                        val audioFile = AudioFileIO.read(file)
                        val tag = audioFile.tagOrCreateAndSetDefault
                        
                        Log.d("HipotifyMetadata", "Setting fields: Title=$title, Artist=$artist, Album=$album, Track=$trackNumber, Date=$releaseDate")
                        tag.setField(FieldKey.TITLE, title ?: "")
                        tag.setField(FieldKey.ARTIST, artist ?: "")
                        tag.setField(FieldKey.ALBUM, album ?: "")
                        if (trackNumber != null && trackNumber > 0) {
                            tag.setField(FieldKey.TRACK, trackNumber.toString())
                        }
                        if (releaseDate != null && releaseDate.isNotEmpty()) {
                            // Extract year if it's a full date
                            val year = if (releaseDate.length >= 4) releaseDate.substring(0, 4) else releaseDate
                            tag.setField(FieldKey.YEAR, year)
                        }
                        
                        if (coverPath != null) {
                            val coverFile = File(coverPath)
                            if (coverFile.exists()) {
                                Log.d("HipotifyMetadata", "Applying artwork from: $coverPath")
                                try {
                                    val bytes = coverFile.readBytes()
                                    Log.d("HipotifyMetadata", "Read ${bytes.size} bytes from cover")
                                    
                                    if (tag is FlacTag) {
                                        Log.d("HipotifyMetadata", "Using FlacTag specific artwork embedding")
                                        val options = BitmapFactory.Options()
                                        options.inJustDecodeBounds = true
                                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                                        
                                        val picture = MetadataBlockDataPicture(
                                            bytes,
                                            PictureTypes.DEFAULT_ID,
                                            "image/jpeg",
                                            "",
                                            options.outWidth,
                                            options.outHeight,
                                            24, // depth
                                            0   // indexed colors
                                        )
                                        tag.deleteArtworkField()
                                        tag.setField(picture)
                                        Log.d("HipotifyMetadata", "Flac artwork set successfully: ${options.outWidth}x${options.outHeight}")
                                    } else {
                                        Log.d("HipotifyMetadata", "Using generic artwork embedding")
                                        val artwork = ArtworkFactory.getNew()
                                        artwork.binaryData = bytes
                                        artwork.mimeType = "image/jpeg"
                                        artwork.pictureType = PictureTypes.DEFAULT_ID
                                        tag.deleteArtworkField()
                                        tag.setField(artwork)
                                        Log.d("HipotifyMetadata", "Generic artwork set successfully")
                                    }
                                } catch (ae: Exception) {
                                    Log.e("HipotifyMetadata", "Error applying artwork: ${ae.message}", ae)
                                }
                            } else {
                                Log.w("HipotifyMetadata", "Cover file does not exist: $coverPath")
                            }
                        }
                        
                        Log.d("HipotifyMetadata", "Committing changes...")
                        audioFile.commit()
                        Log.d("HipotifyMetadata", "Successfully tagged: $path")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("HipotifyMetadata", "Error tagging file: ${e.message}", e)
                        result.error("TAG_ERROR", e.message, null)
                    }
                } else {
                    Log.e("HipotifyMetadata", "Path is null")
                    result.error("INVALID_PATH", "Path cannot be null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun sendAudioSessionBroadcast(sessionId: Int) {
        val i = Intent(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION)
        i.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
        i.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
        i.putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
        sendBroadcast(i)
        Log.d("ViperFix", "Wysłano Broadcast dla sesji: $sessionId")
    }
}
