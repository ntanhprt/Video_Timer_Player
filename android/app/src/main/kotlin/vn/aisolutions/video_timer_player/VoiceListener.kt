package vn.aisolutions.video_timer_player

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Offline Vietnamese speech recognition (sherpa-onnx, Zipformer model trained on ~70k hours,
 * bundled by the build). Listens to the microphone, cuts the audio into utterances at pauses and
 * reports through [emit]: "status", "device", "level" (0..1), "partial" and "final" (text), "error".
 * No Google services or network are needed.
 */
class VoiceListener(private val ctx: Context, private val emit: (String, Any?) -> Unit) {
    private var recognizer: OfflineRecognizer? = null
    private var worker: Thread? = null

    @Volatile private var running = false

    /** Loads the model from the APK assets (a few seconds the first time). */
    @Synchronized
    fun prepare() {
        if (recognizer != null) return
        emit("status", "Đang nạp mô hình giọng nói tiếng Việt...")
        val dir = "model-vi"
        val config = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = OfflineModelConfig(
                transducer = OfflineTransducerModelConfig(
                    encoder = "$dir/encoder.onnx",
                    decoder = "$dir/decoder.onnx",
                    joiner = "$dir/joiner.onnx",
                ),
                tokens = "$dir/tokens.txt",
                numThreads = 2,
            ),
            decodingMethod = "greedy_search",
        )
        recognizer = OfflineRecognizer(ctx.assets, config)
    }

    private val am get() = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val prefs get() = ctx.getSharedPreferences("voice", Context.MODE_PRIVATE)

    private fun typeName(t: Int) = when (t) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Micro của máy"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Tai nghe / loa cắm dây (3.5 mm)"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Tai nghe có dây"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
        AudioDeviceInfo.TYPE_TELEPHONY -> "Điện thoại"
        else -> "Nguồn khác (loại $t)"
    }

    private fun deviceLabel(d: AudioDeviceInfo) = "${typeName(d.type)} — ${d.productName}"

    /** Input sources on the phone right now: [{id, type, label}]. */
    fun inputDevices(): List<Map<String, Any>> =
        am.getDevices(AudioManager.GET_DEVICES_INPUTS).map { mapOf("id" to it.id, "type" to it.type, "label" to deviceLabel(it)) }

    /** The saved choice (an AudioDeviceInfo type), or -1 for "automatic = the phone's own mic". */
    fun savedType(): Int = prefs.getInt("type", -1)

    fun saveChoice(type: Int) {
        prefs.edit().putInt("type", type).apply()
    }

    /** Echo cancelling + noise suppression, to hear the user over the alarm's own music. */
    fun filterOn(): Boolean = prefs.getBoolean("filter", true)

    fun saveFilter(on: Boolean) {
        prefs.edit().putBoolean("filter", on).apply()
    }

    private fun chosenDevice(): AudioDeviceInfo? {
        val all = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val want = savedType()
        return all.firstOrNull { want != -1 && it.type == want } ?: all.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
    }

    private fun decode(rec: OfflineRecognizer, samples: FloatArray): String {
        val stream = rec.createStream()
        try {
            stream.acceptWaveform(samples, 16000)
            rec.decode(stream)
            return rec.getResult(stream).text.trim()
        } finally {
            stream.release()
        }
    }

    fun start() {
        if (running) return
        running = true
        worker = thread(name = "voice-listener") {
            var record: AudioRecord? = null
            val effects = ArrayList<AudioEffect>()
            try {
                prepare()
                val rec = recognizer!!
                val minBuf = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                // Two seconds of buffer so a decode in progress never makes us drop audio.
                val filter = filterOn()
                // VOICE_COMMUNICATION turns on the phone's voice processing (echo and noise
                // cancelling); VOICE_RECOGNITION is the raw, unprocessed signal.
                record = AudioRecord(
                    if (filter) MediaRecorder.AudioSource.VOICE_COMMUNICATION else MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minBuf, 64000),
                )
                if (record.state != AudioRecord.STATE_INITIALIZED) {
                    emit("error", "Không mở được micro (chưa cấp quyền hoặc micro đang bận).")
                    return@thread
                }
                // A speaker/headset on the 3.5 mm jack makes Android pick a headset mic that hears
                // nothing, so the source is chosen explicitly (default: the phone's own microphone).
                val device = chosenDevice()
                if (device != null) record.setPreferredDevice(device)
                val applied = ArrayList<String>()
                if (filter) {
                    val id = record.audioSessionId
                    fun <T : AudioEffect> add(name: String, available: Boolean, create: () -> T?) {
                        try {
                            if (!available) return
                            val e = create() ?: return
                            e.enabled = true
                            effects.add(e)
                            applied.add(name)
                        } catch (_: Throwable) {}
                    }
                    add("khử vọng", AcousticEchoCanceler.isAvailable()) { AcousticEchoCanceler.create(id) }
                    add("giảm ồn", NoiseSuppressor.isAvailable()) { NoiseSuppressor.create(id) }
                    add("tự chỉnh âm lượng", AutomaticGainControl.isAvailable()) { AutomaticGainControl.create(id) }
                }
                record.startRecording()
                emit("status", "listening")
                val label = device?.let { deviceLabel(it) } ?: "micro mặc định"
                emit("device", if (!filter) "$label (không lọc)" else "$label (lọc: ${applied.ifEmpty { listOf("máy không hỗ trợ hiệu ứng, chỉ dùng chế độ thoại") }.joinToString(", ")})")

                val chunk = ShortArray(1600) // 100 ms
                val preRoll = ArrayDeque<FloatArray>()
                var segment = ArrayList<FloatArray>()
                var inSpeech = false
                var silent = 0
                var chunks = 0
                // Quietest 100 ms of the last 5 s: music playing the whole time counts as the
                // room, and the voice has to stand above it.
                val recent = ArrayDeque<Double>()

                fun flatten(parts: List<FloatArray>): FloatArray {
                    val out = FloatArray(parts.sumOf { it.size })
                    var o = 0
                    for (p in parts) { p.copyInto(out, o); o += p.size }
                    return out
                }

                fun finish(keepTail: Boolean = false) {
                    // Drop the trailing silence, keep enough audio for the model to settle.
                    val voiced = segment.size - max(0, silent - 2)
                    if (voiced >= 4) {
                        val text = decode(rec, flatten(segment))
                        if (text.isNotBlank()) emit("final", text)
                    }
                    if (keepTail) {
                        // Cut because it ran long (music never lets it fall silent): the next
                        // piece starts with the last second, so a command is not split in two.
                        segment = ArrayList(segment.takeLast(10))
                        chunks = segment.size
                    } else {
                        segment = ArrayList()
                        inSpeech = false
                        chunks = 0
                    }
                    silent = 0
                }

                while (running) {
                    val n = record.read(chunk, 0, chunk.size)
                    if (n <= 0) continue
                    val f = FloatArray(n)
                    var sum = 0.0
                    for (i in 0 until n) {
                        f[i] = chunk[i] / 32768f
                        sum += f[i].toDouble() * f[i]
                    }
                    val rms = sqrt(sum / n)
                    emit("level", min(1.0, rms * 12))

                    recent.addLast(rms)
                    if (recent.size > 50) recent.removeFirst()
                    val floor = recent.minOrNull() ?: rms
                    val loud = rms > max(0.012, floor * 1.8)

                    if (!inSpeech) {
                        if (loud) {
                            inSpeech = true
                            segment.addAll(preRoll)
                            segment.add(f)
                            silent = 0
                            chunks = 1
                        } else {
                            preRoll.addLast(f)
                            if (preRoll.size > 3) preRoll.removeFirst()
                        }
                        continue
                    }
                    segment.add(f)
                    chunks++
                    silent = if (loud) 0 else silent + 1
                    if (silent >= 7) {
                        finish()
                        preRoll.clear()
                    } else if (segment.size >= 40) {
                        finish(keepTail = true)
                    } else if (chunks % 10 == 0 && segment.size >= 5) {
                        // A running guess so the user sees something while still talking.
                        val text = decode(rec, flatten(segment))
                        if (text.isNotBlank()) emit("partial", text)
                    }
                }
            } catch (e: Throwable) {
                emit("error", e.message ?: e.toString())
            } finally {
                try { record?.stop() } catch (_: Throwable) {}
                for (e in effects) try { e.release() } catch (_: Throwable) {}
                record?.release()
                running = false
            }
        }
    }

    fun stop() {
        running = false
    }
}
