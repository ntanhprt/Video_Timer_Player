package vn.aisolutions.video_timer_player

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Offline speech recognition (Vosk, Vietnamese model bundled by the build) that listens to the
 * microphone and reports what it hears through [emit]: "status", "level" (0..1), "partial", "final".
 * No Google services or network are needed.
 */
class VoiceListener(private val ctx: Context, private val emit: (String, Any?) -> Unit) {
    private var model: Model? = null
    private var worker: Thread? = null

    @Volatile private var running = false

    /** Copies the model out of the APK assets once and loads it. */
    @Synchronized
    fun prepare() {
        if (model != null) return
        val dir = File(ctx.filesDir, "vosk-model-vn")
        val ok = File(dir, ".complete")
        if (!ok.exists()) {
            emit("status", "Đang chuẩn bị mô hình giọng nói (lần đầu)...")
            dir.deleteRecursively()
            copyAsset("model-vn", dir)
            ok.writeText("ok")
        }
        model = Model(dir.absolutePath)
    }

    private fun copyAsset(path: String, dest: File) {
        val children = ctx.assets.list(path) ?: emptyArray()
        if (children.isEmpty()) {
            dest.parentFile?.mkdirs()
            ctx.assets.open(path).use { i -> dest.outputStream().use { o -> i.copyTo(o) } }
        } else {
            dest.mkdirs()
            for (c in children) copyAsset("$path/$c", File(dest, c))
        }
    }

    fun start(grammarJson: String) {
        if (running) return
        running = true
        worker = thread(name = "voice-listener") {
            var record: AudioRecord? = null
            var rec: Recognizer? = null // limited to the command phrases
            var free: Recognizer? = null // free dictation, only to show what was heard
            try {
                prepare()
                rec = Recognizer(model, 16000f, grammarJson)
                free = Recognizer(model, 16000f)
                val minBuf = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                record = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minBuf, 8000),
                )
                if (record.state != AudioRecord.STATE_INITIALIZED) {
                    emit("error", "Không mở được micro (chưa cấp quyền hoặc micro đang bận).")
                    return@thread
                }
                // A speaker/headset on the 3.5 mm jack makes Android pick a headset mic that hears
                // nothing: always use the phone's own microphone.
                val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val builtin = am.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                if (builtin != null) record.setPreferredDevice(builtin)
                record.startRecording()
                emit("status", "listening")
                emit("device", builtin?.productName?.toString() ?: "micro mặc định")
                val buf = ShortArray(1600) // 100 ms
                val bytes = ByteArray(buf.size * 2)
                var lastPartial = ""
                while (running) {
                    val n = record.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    var sum = 0.0
                    for (i in 0 until n) {
                        sum += buf[i].toDouble() * buf[i]
                        bytes[2 * i] = (buf[i].toInt() and 0xff).toByte()
                        bytes[2 * i + 1] = (buf[i].toInt() shr 8).toByte()
                    }
                    val rms = sqrt(sum / n) / 32768.0
                    emit("level", min(1.0, rms * 12)) // speech is usually well under full scale
                    // Commands: the grammar-limited recogniser (reliable). "[unk]" means no command.
                    if (rec.acceptWaveForm(bytes, 2 * n)) {
                        val c = JSONObject(rec.result).optString("text")
                        if (c.isNotBlank() && c != "[unk]") emit("cmd", c)
                    } else {
                        val c = JSONObject(rec.partialResult).optString("partial")
                        if (c.isNotBlank() && c != "[unk]") emit("cmd", c)
                    }
                    // Display: free dictation of whatever was said.
                    if (free.acceptWaveForm(bytes, 2 * n)) {
                        val text = JSONObject(free.result).optString("text")
                        if (text.isNotBlank()) emit("final", text)
                        lastPartial = ""
                    } else {
                        val p = JSONObject(free.partialResult).optString("partial")
                        if (p.isNotBlank() && p != lastPartial) {
                            lastPartial = p
                            emit("partial", p)
                        }
                    }
                }
            } catch (e: Throwable) {
                emit("error", e.message ?: e.toString())
            } finally {
                try { record?.stop() } catch (_: Throwable) {}
                record?.release()
                rec?.close()
                free?.close()
                running = false
            }
        }
    }

    fun stop() {
        running = false
    }
}
