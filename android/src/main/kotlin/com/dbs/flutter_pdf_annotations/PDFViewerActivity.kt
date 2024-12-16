package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileOutputStream

class PDFViewerActivity : AppCompatActivity() {
    private lateinit var pdfRenderer: PdfRenderer
    private lateinit var currentPage: PdfRenderer.Page
    private lateinit var imageView: ImageView
    private lateinit var drawingView: DrawingView
    private var saveFile: File? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Create a vertical linear layout
        val mainLayout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Create a frame layout for PDF and drawing
        val frameLayout = FrameLayout(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        // Create image and drawing views
        imageView = ImageView(this)
        drawingView = DrawingView(this)

        // Add views to frame layout
        frameLayout.addView(imageView)
        frameLayout.addView(drawingView)

        // Create button layout
        val buttonLayout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = android.widget.LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(16, 16, 16, 16)
        }

        // Create save button
        val saveButton = Button(this).apply {
            text = "Save"
            setOnClickListener { savePdf() }
            layoutParams = android.widget.LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(0, 0, 8, 0)
            }
            setBackgroundColor(
                ContextCompat.getColor(
                    this@PDFViewerActivity,
                    android.R.color.holo_green_light
                )
            )
        }

        // Create cancel button
        val cancelButton = Button(this).apply {
            text = "Cancel"
            setOnClickListener {
                drawingView.clearAnnotations()
            }
            layoutParams = android.widget.LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(8, 0, 0, 0)
            }
            setBackgroundColor(
                ContextCompat.getColor(
                    this@PDFViewerActivity,
                    android.R.color.holo_red_light
                )
            )
        }

        // Add buttons to button layout
        buttonLayout.addView(saveButton)
        buttonLayout.addView(cancelButton)

        // Add frame and button layouts to main layout
        mainLayout.addView(frameLayout)
        mainLayout.addView(buttonLayout)

        // Set the content view
        setContentView(mainLayout)

        // Get paths
        val filePath = intent?.getStringExtra("filePath")
        val savePath = intent?.getStringExtra("savePath")

        if (filePath.isNullOrEmpty() || savePath.isNullOrEmpty()) {
            Toast.makeText(this, "Invalid file path", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        saveFile = File(savePath)
        openPdf(filePath)
    }

    private fun openPdf(filePath: String) {
        try {
            val file = File(filePath)
            val fileDescriptor =
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            pdfRenderer = PdfRenderer(fileDescriptor)

            // Open the first page
            currentPage = pdfRenderer.openPage(0)
            val bitmap =
                Bitmap.createBitmap(currentPage.width, currentPage.height, Bitmap.Config.ARGB_8888)
            currentPage.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            // Display the PDF and prepare for annotation
            imageView.setImageBitmap(bitmap)
            drawingView.setBitmap(bitmap)
        } catch (e: Exception) {
            Toast.makeText(this, "Failed to open PDF: ${e.message}", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        currentPage.close()
        pdfRenderer.close()
    }

    private fun savePdf() {
        try {
            val outputStream = FileOutputStream(saveFile)
            drawingView.getAnnotatedBitmap()?.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            outputStream.close()
            Toast.makeText(this, "PDF saved successfully at ${saveFile?.path}", Toast.LENGTH_SHORT)
                .show()
            finish()
        } catch (e: Exception) {
            Toast.makeText(this, "Error saving PDF: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }
}
