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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.aisolutions/ytdlp")
            .setMethodCallHandler { call, result ->
                if (call.method != "download") return@setMethodCallHandler result.notImplemented()
                val url = call.argument<String>("url")!!
                val out = call.argument<String>("out")!!
                thread {
                    val reply: Pair<String?, String?> = try {
                        YoutubeDL.getInstance().init(applicationContext)
                        File(out).parentFile?.mkdirs()
                        File(out).delete()
                        val req = YoutubeDLRequest(url)
                        req.addOption("-f", "bestaudio[ext=m4a]/bestaudio")
                        req.addOption("--no-playlist")
                        req.addOption("-o", out)
                        YoutubeDL.getInstance().execute(req, null, null)
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
