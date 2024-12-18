package com.dbs.flutter_pdf_annotations
import android.graphics.*
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.*
import android.view.*
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.io.*

class PDFViewerActivity : AppCompatActivity() {
    private var pdfRenderer: PdfRenderer? = null
    private var currentPage: PdfRenderer.Page? = null
    private var currentPageIndex = 0
    private var pageCount = 0
    private lateinit var scrollView: ScrollView
    private lateinit var pdfContainer: LinearLayout
    private lateinit var drawingView: DrawingView
    private lateinit var toolbarView: FloatingToolbar
    private var isDrawingEnabled = false
    private var currentPageAnnotations = mutableMapOf<Int, List<DrawingView.AnnotationData>>()
    private var pdfDocument: PdfDocument? = null
    private var originalPdfPath: String? = null
    private var currentBitmap: Bitmap? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val mainLayout = FrameLayout(this)

        scrollView = ScrollView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        pdfContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        scrollView.addView(pdfContainer)

        drawingView = DrawingView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            visibility = View.GONE
            isEnabled = false
        }

        toolbarView = FloatingToolbar(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = 50
                leftMargin = 50
            }
            onDrawingToggled = { enabled ->
                toggleDrawingMode(enabled)
            }
            onColorSelected = {
                showColorPicker()
            }
            onStrokeWidthChanged = { width ->
                drawingView.setStrokeWidth(width)
            }
            onUndoClicked = {
                drawingView.undo()
            }
            onClearClicked = {
                drawingView.clearAnnotations()
            }
        }

        val buttonsLayout = createNavigationButtons()

        mainLayout.addView(scrollView)
        mainLayout.addView(drawingView)
        mainLayout.addView(toolbarView)
        mainLayout.addView(buttonsLayout)

        setContentView(mainLayout)

        originalPdfPath = intent?.getStringExtra("filePath")
            ?: return finishWithError("Missing file path")

        openPdf(originalPdfPath!!)
        showPage(0)
    }

    private fun createNavigationButtons(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM
            }
            setBackgroundColor(Color.WHITE)
            elevation = 8f
            setPadding(16, 16, 16, 16)

            Button(context).apply {
                text = "Previous"
                setOnClickListener {
                    saveCurrentPageAnnotations()
                    showPreviousPage()
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginEnd = 8
                }
                addView(this)
            }

            Button(context).apply {
                text = "Next"
                setOnClickListener {
                    saveCurrentPageAnnotations()
                    showNextPage()
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginEnd = 8
                }
                addView(this)
            }

            Space(context).apply {
                layoutParams = LinearLayout.LayoutParams(0, 0, 1f)
            }.also { addView(it) }

            Button(context).apply {
                text = "Save"
                setOnClickListener { saveAndFinish() }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginStart = 8
                }
                addView(this)
            }

            Button(context).apply {
                text = "Cancel"
                setOnClickListener { finish() }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginStart = 8
                }
                addView(this)
            }
        }
    }

    private fun showColorPicker() {
        val colorPicker = ColorPickerDialog(this)
        colorPicker.setOnColorSelectedListener { color ->
            drawingView.setColor(color)
        }
        colorPicker.show()
    }

    private fun openPdf(filePath: String) {
        try {
            val file = File(filePath)
            if (!file.exists()) throw FileNotFoundException("File not found at path: $filePath")

            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            pdfRenderer = PdfRenderer(descriptor)
            pageCount = pdfRenderer?.pageCount ?: 0
            pdfDocument = PdfDocument()
        } catch (e: Exception) {
            finishWithError("Error opening PDF: ${e.message}")
        }
    }

    private fun showPage(pageIndex: Int) {
        if (pageIndex < 0 || pageIndex >= pageCount) return

        try {
            saveCurrentPageAnnotations()
            currentPage?.close()
            currentBitmap?.recycle()

            pdfRenderer?.let { renderer ->
                currentPage = renderer.openPage(pageIndex).also { page ->
                    currentPageIndex = pageIndex

                    currentBitmap = Bitmap.createBitmap(
                        page.width,
                        page.height,
                        Bitmap.Config.ARGB_8888
                    ).also { bitmap ->
                        val canvas = Canvas(bitmap)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                        currentPageAnnotations[pageIndex]?.forEach { annotationData ->
                            val paint = Paint().apply {
                                color = annotationData.color
                                strokeWidth = annotationData.strokeWidth
                                style = Paint.Style.STROKE
                                strokeJoin = Paint.Join.ROUND
                                strokeCap = Paint.Cap.ROUND
                            }
                            canvas.drawPath(annotationData.path, paint)
                        }

                        pdfContainer.removeAllViews()
                        val imageView = ImageView(this).apply {
                            setImageBitmap(bitmap)
                            scaleType = ImageView.ScaleType.FIT_CENTER
                            adjustViewBounds = true
                        }
                        pdfContainer.addView(imageView)

                        imageView.post {
                            val location = IntArray(2)
                            imageView.getLocationInWindow(location)

                            val bounds = RectF(
                                0f,
                                0f,
                                imageView.width.toFloat(),
                                imageView.height.toFloat()
                            )

                            val windowInsets = imageView.rootWindowInsets
                            val statusBarHeight = windowInsets?.getInsets(WindowInsets.Type.statusBars())?.top ?: 0

                            bounds.offset(location[0].toFloat(), location[1].toFloat() - statusBarHeight)

                            drawingView.setPdfViewBounds(bounds)
                            drawingView.setPageSize(page.width, page.height)
                            drawingView.visibility = if (isDrawingEnabled) View.VISIBLE else View.GONE
                        }
                    }
                }
            }
        } catch (e: Exception) {
            finishWithError("Error showing page: ${e.message}")
        }
    }

    private fun saveCurrentPageAnnotations() {
        val annotations = drawingView.getAnnotations()
        if (annotations.isNotEmpty()) {
            currentPageAnnotations[currentPageIndex] = annotations
            drawingView.clearAnnotations()
        }
    }

    private fun toggleDrawingMode(enabled: Boolean) {
        isDrawingEnabled = enabled
        drawingView.isEnabled = enabled
        drawingView.visibility = if (enabled) View.VISIBLE else View.GONE
    }

    private fun saveAndFinish() {
        try {
            saveCurrentPageAnnotations()
            currentPage?.close()
            currentPage = null

            val document = PdfDocument()

            for (i in 0 until pageCount) {
                pdfRenderer?.openPage(i)?.use { page ->
                    val pageInfo = PdfDocument.PageInfo.Builder(page.width, page.height, i).create()
                    val documentPage = document.startPage(pageInfo)

                    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    documentPage.canvas.drawBitmap(bitmap, 0f, 0f, null)

                    currentPageAnnotations[i]?.forEach { annotationData ->
                        val paint = Paint().apply {
                            color = annotationData.color
                            strokeWidth = annotationData.strokeWidth
                            style = Paint.Style.STROKE
                            strokeJoin = Paint.Join.ROUND
                            strokeCap = Paint.Cap.ROUND
                        }
                        documentPage.canvas.drawPath(annotationData.path, paint)
                    }

                    document.finishPage(documentPage)
                    bitmap.recycle()
                }
            }

            val savePath = intent.getStringExtra("savePath")
            if (savePath.isNullOrBlank()) {
                Toast.makeText(this, "Error: Save path not provided", Toast.LENGTH_LONG).show()
                FlutterPdfAnnotationsPlugin.notifySaveResult(null)
                finish()
                return
            }

            val outputFile = File(savePath).absoluteFile
            outputFile.parentFile?.mkdirs()

            if (!outputFile.parentFile?.canWrite()!!) {
                Toast.makeText(this, "Error: Cannot write to specified directory", Toast.LENGTH_LONG).show()
                FlutterPdfAnnotationsPlugin.notifySaveResult(null)
                finish()
                return
            }

            FileOutputStream(outputFile).use { out ->
                document.writeTo(out)
            }
            document.close()

            Toast.makeText(this, "PDF saved successfully!", Toast.LENGTH_LONG).show()
            FlutterPdfAnnotationsPlugin.notifySaveResult(outputFile.absolutePath)
            finish()

        } catch (e: Exception) {
            val errorMessage = "Error saving PDF: ${e.message}"
            Toast.makeText(this, errorMessage, Toast.LENGTH_LONG).show()
            FlutterPdfAnnotationsPlugin.notifySaveResult(null)
            finish()
        }
    }

    private fun showNextPage() {
        if (currentPageIndex < pageCount - 1) {
            showPage(currentPageIndex + 1)
        }
    }

    private fun showPreviousPage() {
        if (currentPageIndex > 0) {
            showPage(currentPageIndex - 1)
        }
    }

    private fun finishWithError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        currentPage?.close()
        pdfRenderer?.close()
        currentBitmap?.recycle()
        pdfDocument?.close()
    }
}