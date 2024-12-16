package com.example.flutter_pdf_annotations

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class PdfActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Load your custom layout to show PDF (e.g., activity_pdf.xml)
        setContentView(R.layout.activity_pdf)

        val filePath = intent.getStringExtra("filePath")
        val savePath = intent.getStringExtra("savePath")

        // Add logic to render the PDF and enable annotations
    }
}
