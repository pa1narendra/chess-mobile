package com.example.real_chess_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Explicitly allow screenshots
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
