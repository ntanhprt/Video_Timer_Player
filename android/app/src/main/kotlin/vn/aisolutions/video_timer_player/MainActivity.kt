package vn.aisolutions.video_timer_player

import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/** Bridges Dart to yt-dlp (bundled by youtubedl-android) for downloading a link's audio. */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var voiceChannel: MethodChannel? = null
    private val voice = VoiceListener(this) { event, value -> main.post { voiceChannel?.invokeMethod(event, value) } }

    private fun log(msg: String) = main.post { channel?.invokeMethod("log", msg) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.aisolutions/voice")
        voiceChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> thread {
                    try { voice.prepare() } catch (e: Throwable) { main.post { voiceChannel?.invokeMethod("error", e.message) } }
                }
                "start" -> voice.start()
                "stop" -> voice.stop()
                "inputDevices" -> return@setMethodCallHandler result.success(voice.inputDevices())
                "savedInputType" -> return@setMethodCallHandler result.success(voice.savedType())
                "saveInputType" -> voice.saveChoice(call.argument<Int>("type") ?: -1)
                "filterOn" -> return@setMethodCallHandler result.success(voice.filterOn())
                "saveFilter" -> voice.saveFilter(call.argument<Boolean>("on") ?: true)
                else -> return@setMethodCallHandler result.notImplemented()
            }
            result.success(null)
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.aisolutions/ytdlp")
        channel!!.setMethodCallHandler { call, result ->
                if (call.method != "download") return@setMethodCallHandler result.notImplemented()
                val url = call.argument<String>("url")!!
                val out = call.argument<String>("out")!!
                val titleOut = call.argument<String>("titleOut")
                thread {
                    val reply: Pair<String?, String?> = try {
                        log("Khởi tạo yt-dlp...")
                        YoutubeDL.getInstance().init(applicationContext)
                        run {
                            // Always update first: YouTube changes often and an old yt-dlp gets 403.
                            log("Cập nhật yt-dlp bản mới nhất (cần mạng)...")
                            try {
                                val st = YoutubeDL.getInstance().updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)
                                log("Cập nhật yt-dlp: $st, phiên bản ${YoutubeDL.getInstance().versionName(applicationContext)}")
                            } catch (e: Throwable) {
                                log("Không cập nhật được yt-dlp: ${e.message}")
                            }
                        }
                        log("Đang lấy và tải âm thanh...")
                        File(out).parentFile?.mkdirs()
                        File(out).delete()
                        val req = YoutubeDLRequest(url)
                        // Audio only (never video). Best AAC while the file stays under 64 MB; a long video
                        // falls back to the low-bitrate AAC so it does not take hundreds of MB.
                        req.addOption("-f", "bestaudio[ext=m4a][filesize<64M]/bestaudio[ext=m4a][abr<=70]/bestaudio[ext=m4a]/bestaudio")
                        req.addOption("--no-playlist")
                        if (titleOut != null) {
                            // Save the video title next to the audio so the app can list it by name.
                            File(titleOut).delete()
                            req.addOption("--print-to-file")
                            req.addOption("%(title)s")
                            req.addOption(titleOut)
                        }
                        req.addOption("-o", out)
                        YoutubeDL.getInstance().execute(req) { progress, eta, line ->
                            val l = line.trim()
                            if (l.isNotEmpty()) log("yt-dlp ${progress.toInt()}% (còn ${eta}s): $l")
                        }
                        if (File(out).length() > 0) Pair(out, null) else Pair(null, "yt-dlp không tạo ra tệp")
                    } catch (e: Throwable) {
                        Pair(null, e.message ?: e.toString())
                    }
                    main.post {
                        if (reply.first != null) result.success(reply.first) else result.error("ytdlp", reply.second, null)
                    }
                }
            }
    }
}
