package com.vanta.ffpanel

import android.content.Context
import android.graphics.Bitmap

class Detector(context: Context) : AutoCloseable {
    fun detect(frame: Bitmap): List<Detection> {
        // الذكاء الاصطناعي مقفول مؤقتاً عشان التطبيق ميعملش كراش على رام 4 جيجا
        return emptyList() 
    }
    override fun close() {}
}
