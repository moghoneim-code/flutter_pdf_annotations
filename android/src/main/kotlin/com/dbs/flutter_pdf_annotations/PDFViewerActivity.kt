package com.dbs.flutter_pdf_annotations

import android.graphics.*
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.*
import android.view.Gravity
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import java.io.*

class PDFViewerActivity : AppCompatActivity() {
    private var pdfRenderer: PdfRenderer? = null
    private var currentPage: PdfRenderer.Page? = null
    private lateinit var imageView: ImageView
    private lateinit var drawingView: DrawingView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Main Layout
        val mainLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val frameLayout = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }

        imageView = ImageView(this)
        drawingView = DrawingView(this)
        frameLayout.addView(imageView)
        frameLayout.addView(drawingView)

        val buttonLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(16, 16, 16, 16)
        }

        val saveButton = Button(this).apply {
            text = "Save"
            setOnClickListener { saveToOriginalPath() }
            setBackgroundColor(ContextCompat.getColor(this@PDFViewerActivity, android.R.color.holo_green_light))
        }
        val cancelButton = Button(this).apply {
            text = "Cancel"
            setOnClickListener { drawingView.clearAnnotations() }
            setBackgroundColor(ContextCompat.getColor(this@PDFViewerActivity, android.R.color.holo_red_light))
        }

        buttonLayout.addView(saveButton)
        buttonLayout.addView(cancelButton)

        mainLayout.addView(frameLayout)
        mainLayout.addView(buttonLayout)
        setContentView(mainLayout)

        val filePath = intent?.getStringExtra("filePath") ?: return finishWithError("Missing file path")
        openPdf(filePath)
    }

    private fun saveToOriginalPath() {
        try {
            val originalPath = intent?.getStringExtra("filePath") ?: throw Exception("Missing original file path")
            val annotatedBitmap = drawingView.getAnnotatedBitmap() ?: throw Exception("No annotation found")

            val originalFile = File(originalPath)
            if (!originalFile.exists()) throw FileNotFoundException("Original file not found: $originalPath")

            // Step 1: Save to a temporary file
            val tempFile = File(originalFile.parent, "temp_annotated_${System.currentTimeMillis()}.pdf")
            saveAnnotatedPdfToFile(originalFile, tempFile, annotatedBitmap)

            // Step 2: Replace the original file with the temporary file
            if (originalFile.delete()) {
                if (tempFile.renameTo(originalFile)) {
                    FlutterPdfAnnotationsPlugin.notifySaveResult(originalFile.absolutePath)
                    Toast.makeText(this, "PDF saved successfully!", Toast.LENGTH_SHORT).show()
                    finish()
                } else {
                    throw Exception("Failed to replace the original file")
                }
            } else {
                throw Exception("Failed to delete the original file")
            }
        } catch (e: Exception) {
            FlutterPdfAnnotationsPlugin.notifySaveResult(null)
            Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun saveAnnotatedPdfToFile(originalFile: File, outputFile: File, annotatedBitmap: Bitmap) {
        FileOutputStream(outputFile).use { outputStream ->
            val renderer = PdfRenderer(ParcelFileDescriptor.open(originalFile, ParcelFileDescriptor.MODE_READ_ONLY))
            val pdfDocument = PdfDocument()

            for (i in 0 until renderer.pageCount) {
                val page = renderer.openPage(i)
                val pageInfo = PdfDocument.PageInfo.Builder(page.width, page.height, i + 1).create()
                val pdfPage = pdfDocument.startPage(pageInfo)
                val canvas = pdfPage.canvas

                // Draw the original PDF content
                val originalBitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                page.render(originalBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                canvas.drawBitmap(originalBitmap, 0f, 0f, null)

                // Draw annotations only on the first page
                if (i == 0) {
                    canvas.drawBitmap(annotatedBitmap, 0f, 0f, null)
                }

                pdfDocument.finishPage(pdfPage)
                page.close()
            }

            // Write the new PDF
            pdfDocument.writeTo(outputStream)
            pdfDocument.close()
            renderer.close()
        }
    }


    private fun openPdf(filePath: String) {
        try {
            val file = File(filePath)
            if (!file.exists()) throw FileNotFoundException("File not found at path: $filePath")

            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            pdfRenderer = PdfRenderer(descriptor)

            currentPage = pdfRenderer?.openPage(0)
            currentPage?.let { page ->
                val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                imageView.setImageBitmap(bitmap)
                drawingView.setBitmap(bitmap)
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun finishWithError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        currentPage?.close()
        pdfRenderer?.close()
    }
}
