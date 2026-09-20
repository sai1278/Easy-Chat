package com.nearbyconnect.app

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val AUDIO_CHANNEL = "com.nearbyconnect.app/audio_player"
    private var mediaPlayer: MediaPlayer? = null
    private var currentlyPlayingUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "Audio URL cannot be null or empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        mediaPlayer = null

                        val mp = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .build()
                            )
                            setDataSource(url)
                            setOnPreparedListener { player ->
                                currentlyPlayingUrl = url
                                player.start()
                                result.success(true)
                            }
                            setOnCompletionListener { player ->
                                currentlyPlayingUrl = null
                                player.release()
                                mediaPlayer = null
                            }
                            setOnErrorListener { player, what, extra ->
                                currentlyPlayingUrl = null
                                player.release()
                                mediaPlayer = null
                                result.error("PLAYBACK_ERROR", "MediaPlayer error: what=$what, extra=$extra", null)
                                true
                            }
                            prepareAsync()
                        }
                        mediaPlayer = mp
                    } catch (e: Exception) {
                        currentlyPlayingUrl = null
                        mediaPlayer?.release()
                        mediaPlayer = null
                        result.error("PLAYBACK_EXCEPTION", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        mediaPlayer = null
                        currentlyPlayingUrl = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_EXCEPTION", e.message, null)
                    }
                }
                "isPlaying" -> {
                    val playing = try {
                        mediaPlayer?.isPlaying == true
                    } catch (e: Exception) {
                        false
                    }
                    result.success(playing)
                }
                "getPlayingUrl" -> {
                    result.success(currentlyPlayingUrl)
                }
                "openMaps" -> {
                    val mapsUrl = call.argument<String>("url")
                    if (!mapsUrl.isNullOrEmpty()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(mapsUrl))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MAPS_EXCEPTION", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Maps URL cannot be null or empty", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
