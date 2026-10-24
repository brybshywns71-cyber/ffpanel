package com.vanta.ffpanel

import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.max
import kotlin.math.min

class Detector(context: Context) : AutoCloseable {

    companion object {
        // الموديل الجديد بتاع YOLOv8
        private const val MODEL_FILE = "best-fp16.tflite" 
        private const val INPUT_SIZE = 320 // تصغير الصورة عشان السرعة
        private const val SCORE_THRESHOLD = 0.45f
        private const val IOU_THRESHOLD = 0.45f
    }

    private val interpreter: Interpreter
    private val inputBuffer: ByteBuffer
    private val isQuantInput: Boolean

    init {
        interpreter = Interpreter(loadModel(context), Interpreter.Options().apply { setNumThreads(4) })
        isQuantInput = interpreter.getInputTensor(0).dataType() == DataType.UINT8
        inputBuffer = ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3 * 4)
            .order(ByteOrder.nativeOrder())
    }

    fun detect(frame: Bitmap): List<Detection> {
        val scaled = Bitmap.createScaledBitmap(frame, INPUT_SIZE, INPUT_SIZE, true)
        inputBuffer.rewind()
        val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
        scaled.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
        
        for (p in pixels) {
            inputBuffer.putFloat(((p shr 16) and 0xFF) / 255f)
            inputBuffer.putFloat(((p shr 8) and 0xFF) / 255f)
            inputBuffer.putFloat((p and 0xFF) / 255f)
        }
        inputBuffer.rewind()
        
        // YOLOv8 output: [1, 84, 8400] -> 84 = 4 (box) + 80 classes (or 1 class for FF)
        val output = Array(1) { Array(84) { FloatArray(8400) } }
        interpreter.run(inputBuffer, output)
        if (scaled !== frame) scaled.recycle()

        val sw = DetectionBridge.screenW
        val sh = DetectionBridge.screenH
        if (sw <= 0 || sh <= 0) return emptyList()

        val detections = ArrayList<Detection>()
        
        // تحليل المخرجات (YOLOv8 post-processing)
        for (i in 0 until 8400) {
            // لو الموديل بتاع فري فاير، الكلاس 0 هو اللاعب
            val classProb = output[0][4][i]
            if (classProb < SCORE_THRESHOLD) continue

            val cx = output[0][0][i] * sw
            val cy = output[0][1][i] * sh
            val w = output[0][2][i] * sw
            val h = output[0][3][i] * sh

            val left = cx - (w / 2)
            val top = cy - (h / 2)
            val right = cx + (w / 2)
            val bottom = cy + (h / 2)

            detections.add(Detection(left, top, right, bottom, classProb))
        }

        // دالة NMS (عشان ميرسمش 100 مربع على نفس اللاعب)
        return applyNMS(detections)
    }

    private fun applyNMS(dets: List<Detection>): List<Detection> {
        val sorted = dets.sortedByDescending { it.score }
        val result = ArrayList<Detection>()
        val active = BooleanArray(sorted.size) { true }

        for (i in sorted.indices) {
            if (!active[i]) continue
            val a = sorted[i]
            result.add(a)
            for (j in i + 1 until sorted.size) {
                if (active[j] && calculateIoU(a, sorted[j]) > IOU_THRESHOLD) {
                    active[j] = false
                }
            }
        }
        return result
    }

    private fun calculateIoU(a: Detection, b: Detection): Float {
        val x1 = max(a.left, b.left)
        val y1 = max(a.top, b.top)
        val x2 = min(a.right, b.right)
        val y2 = min(a.bottom, b.bottom)
        val w = max(0f, x2 - x1)
        val h = max(0f, y2 - y1)
        val inter = w * h
        val areaA = (a.right - a.left) * (a.bottom - a.top)
        val areaB = (b.right - b.left) * (b.bottom - b.top)
        return inter / (areaA + areaB - inter)
    }

    private fun loadModel(context: Context): MappedByteBuffer {
        context.assets.openFd(MODEL_FILE).use { fd ->
            FileInputStream(fd.fileDescriptor).use { fis ->
                return fis.channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
            }
        }
    }
    override fun close() { try { interpreter.close() } catch (_: Throwable) {} }
}
