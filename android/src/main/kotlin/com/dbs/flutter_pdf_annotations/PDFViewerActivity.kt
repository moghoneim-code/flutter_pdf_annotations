package com.dbs.flutter_pdf_annotations

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.*
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import com.google.android.material.bottomsheet.BottomSheetDialog
import java.io.*
import kotlinx.coroutines.*

class PDFViewerActivity : AppCompatActivity() {
    private var pdfRenderer: PdfRenderer? = null
    private var pageCount = 0
    private lateinit var scrollView: LockableScrollView
    private lateinit var pdfContainer: LinearLayout
    private val drawingViews = mutableListOf<DrawingView>()
    private val undoStack = mutableListOf<Int>()
    private var currentColor = Color.RED
    private var currentStrokeWidth = 8f
    private var currentEraserMode = false
    private var currentHighlightColor = Color.argb(128, 255, 255, 0)
    private var originalPdfPath: String? = null

    private val availableImages = mutableListOf<Bitmap>()

    private enum class AnnotationMode { NONE, DRAW, ERASE, HIGHLIGHT, IMAGE }
    private var annotationMode = AnnotationMode.NONE

    private lateinit var drawBtn: LinearLayout
    private lateinit var highlightBtn: LinearLayout
    private lateinit var eraserBtn: LinearLayout
    private lateinit var colorSwatch: View
    private lateinit var sizeSmallBtn: TextView
    private lateinit var sizeMediumBtn: TextView
    private lateinit var sizeLargeBtn: TextView
    private var imageBtn: LinearLayout? = null

    // Bottom bar: swaps between normal tools and image-action buttons
    private lateinit var normalBarContent: LinearLayout
    private lateinit var imageActionContent: LinearLayout
    private var activeImageView: DrawingView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        originalPdfPath = intent?.getStringExtra("filePath")
            ?: run { finishWithError("Missing file path"); return }

        applyIntentConfig()

        val topBarHeight = dpToPx(56)
        val bottomBarHeight = dpToPx(72)

        val mainLayout = FrameLayout(this)

        scrollView = LockableScrollView(this)
        scrollView.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )

        pdfContainer = LinearLayout(this)
        pdfContainer.orientation = LinearLayout.VERTICAL
        pdfContainer.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        pdfContainer.setPadding(0, topBarHeight, 0, bottomBarHeight)
        scrollView.addView(pdfContainer)

        val title = intent.getStringExtra("title") ?: "PDF Annotations"
        val topBar = buildTopBar(title)
        val bottomBar = buildBottomBar()

        mainLayout.addView(scrollView)

        val topBarLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        topBarLp.gravity = Gravity.TOP
        mainLayout.addView(topBar, topBarLp)

        val bottomBarLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        bottomBarLp.gravity = Gravity.BOTTOM
        mainLayout.addView(bottomBar, bottomBarLp)

        setContentView(mainLayout)
        openAndRenderPdf(originalPdfPath!!)
    }

    private fun applyIntentConfig() {
        if (intent.hasExtra("initialPenColor"))
            currentColor = intent.getIntExtra("initialPenColor", currentColor)
        if (intent.hasExtra("initialHighlightColor"))
            currentHighlightColor = intent.getIntExtra("initialHighlightColor", currentHighlightColor)
        if (intent.hasExtra("initialStrokeWidth"))
            currentStrokeWidth = intent.getFloatExtra("initialStrokeWidth", currentStrokeWidth)

        intent.getStringArrayListExtra("imagePaths")?.forEach { path ->
            try {
                val bmp = BitmapFactory.decodeFile(path)
                if (bmp != null) availableImages.add(bmp)
            } catch (_: Exception) {}
        }
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()

    /** Show Apply/Delete bar; hide normal tools. */
    private fun showImageActions(dv: DrawingView) {
        activeImageView = dv
        normalBarContent.visibility = View.GONE
        imageActionContent.visibility = View.VISIBLE
    }

    /** Restore normal tools bar. */
    private fun hideImageActions() {
        activeImageView = null
        normalBarContent.visibility = View.VISIBLE
        imageActionContent.visibility = View.GONE
    }

    private fun buildTopBar(title: String = "PDF Annotations"): LinearLayout {
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setBackgroundColor(Color.WHITE)
        bar.elevation = dpToPx(4).toFloat()
        bar.setPadding(dpToPx(8), dpToPx(8), dpToPx(8), dpToPx(8))

        val cancelBtn = Button(this)
        cancelBtn.text = "Cancel"
        cancelBtn.setTextColor(Color.parseColor("#2196F3"))
        cancelBtn.background = null
        cancelBtn.setOnClickListener { finish() }
        bar.addView(cancelBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        val titleView = TextView(this)
        titleView.text = title
        titleView.textSize = 16f
        titleView.setTextColor(Color.BLACK)
        titleView.gravity = Gravity.CENTER
        bar.addView(titleView, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val shareBtn = ImageButton(this)
        shareBtn.setImageResource(android.R.drawable.ic_menu_share)
        shareBtn.background = null
        shareBtn.setOnClickListener { shareAndSave() }
        val shareLp = LinearLayout.LayoutParams(dpToPx(48), dpToPx(48))
        shareLp.marginEnd = dpToPx(4)
        bar.addView(shareBtn, shareLp)

        return bar
    }

    /**
     * Returns a FrameLayout that contains two layers:
     *  - normalBarContent  : the regular tool buttons (visible by default)
     *  - imageActionContent: Apply / Delete buttons (gone by default, shown when image selected)
     */
    private fun buildBottomBar(): FrameLayout {
        val container = FrameLayout(this)
        container.setBackgroundColor(Color.WHITE)
        container.elevation = dpToPx(8).toFloat()

        // ── Normal tools ──────────────────────────────────────────────────────
        normalBarContent = LinearLayout(this)
        normalBarContent.orientation = LinearLayout.HORIZONTAL
        normalBarContent.gravity = Gravity.CENTER_VERTICAL
        normalBarContent.setPadding(dpToPx(2), dpToPx(8), dpToPx(2), dpToPx(8))

        drawBtn = makeToolButton("Draw", android.R.drawable.ic_menu_edit) { toggleMode(AnnotationMode.DRAW) }
        highlightBtn = makeToolButton("Highlight", android.R.drawable.ic_menu_crop) { toggleMode(AnnotationMode.HIGHLIGHT) }
        eraserBtn = makeToolButton("Eraser", android.R.drawable.ic_menu_close_clear_cancel) { toggleMode(AnnotationMode.ERASE) }

        normalBarContent.addView(drawBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))
        normalBarContent.addView(highlightBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))
        normalBarContent.addView(eraserBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))

        if (availableImages.isNotEmpty()) {
            val btn = makeToolButton("Image", android.R.drawable.ic_menu_gallery) { toggleMode(AnnotationMode.IMAGE) }
            imageBtn = btn
            normalBarContent.addView(btn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))
        }

        colorSwatch = View(this)
        val swatchSize = dpToPx(36)
        val swatchLp = LinearLayout.LayoutParams(swatchSize, swatchSize)
        swatchLp.gravity = Gravity.CENTER_VERTICAL
        swatchLp.marginStart = dpToPx(4)
        swatchLp.marginEnd = dpToPx(4)
        colorSwatch.layoutParams = swatchLp
        val swatchBg = GradientDrawable()
        swatchBg.shape = GradientDrawable.OVAL
        swatchBg.setColor(currentColor)
        colorSwatch.background = swatchBg
        colorSwatch.isClickable = true
        colorSwatch.setOnClickListener { showColorPicker() }
        normalBarContent.addView(colorSwatch)

        sizeSmallBtn = makeSizeButton("S", 3f)
        sizeMediumBtn = makeSizeButton("M", 8f)
        sizeLargeBtn = makeSizeButton("L", 18f)
        normalBarContent.addView(sizeSmallBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 0.7f))
        normalBarContent.addView(sizeMediumBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 0.7f))
        normalBarContent.addView(sizeLargeBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 0.7f))
        updateSizeButtons(when {
            currentStrokeWidth <= 4f -> "S"
            currentStrokeWidth >= 14f -> "L"
            else -> "M"
        })

        val undoBtn = makeToolButton("Undo", android.R.drawable.ic_menu_revert) {
            if (undoStack.isNotEmpty()) {
                val pageIdx = undoStack.removeAt(undoStack.size - 1)
                drawingViews.getOrNull(pageIdx)?.undo()
            }
        }
        normalBarContent.addView(undoBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val clearBtn = makeToolButton("Clear", android.R.drawable.ic_menu_delete) {
            AlertDialog.Builder(this)
                .setTitle("Clear All?")
                .setMessage("This will remove all annotations.")
                .setPositiveButton("Clear") { _, _ -> drawingViews.forEach { it.clearAnnotations() }; undoStack.clear() }
                .setNegativeButton("Cancel", null)
                .show()
        }
        normalBarContent.addView(clearBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val saveBtn = Button(this)
        saveBtn.text = "Save"
        saveBtn.setTextColor(Color.WHITE)
        saveBtn.setBackgroundColor(Color.parseColor("#2196F3"))
        saveBtn.setOnClickListener { saveAndFinish() }
        normalBarContent.addView(saveBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))

        container.addView(normalBarContent, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // ── Image action bar (Apply / Delete) ─────────────────────────────────
        imageActionContent = LinearLayout(this)
        imageActionContent.orientation = LinearLayout.HORIZONTAL
        imageActionContent.gravity = Gravity.CENTER_VERTICAL
        imageActionContent.setPadding(dpToPx(24), dpToPx(10), dpToPx(24), dpToPx(10))
        imageActionContent.visibility = View.GONE

        val applyBtn = Button(this)
        applyBtn.text = "✓  Apply"
        applyBtn.textSize = 16f
        applyBtn.setTextColor(Color.WHITE)
        applyBtn.setBackgroundColor(Color.parseColor("#4CAF50"))
        applyBtn.setOnClickListener {
            activeImageView?.acceptSelectedImage()
        }
        val applyLp = LinearLayout.LayoutParams(0, dpToPx(52), 1f)
        applyLp.marginEnd = dpToPx(16)
        imageActionContent.addView(applyBtn, applyLp)

        val deleteBtn = Button(this)
        deleteBtn.text = "✕  Delete"
        deleteBtn.textSize = 16f
        deleteBtn.setTextColor(Color.WHITE)
        deleteBtn.setBackgroundColor(Color.parseColor("#F44336"))
        deleteBtn.setOnClickListener {
            activeImageView?.deleteSelectedImage()
        }
        imageActionContent.addView(deleteBtn, LinearLayout.LayoutParams(0, dpToPx(52), 1f))

        container.addView(imageActionContent, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        return container
    }

    private fun makeToolButton(label: String, iconRes: Int, onClick: () -> Unit): LinearLayout {
        val container = LinearLayout(this)
        container.orientation = LinearLayout.VERTICAL
        container.gravity = Gravity.CENTER
        container.setPadding(dpToPx(2), dpToPx(2), dpToPx(2), dpToPx(2))
        container.setOnClickListener { onClick() }

        val icon = ImageView(this)
        icon.setImageResource(iconRes)
        icon.setColorFilter(Color.parseColor("#9E9E9E"))
        val iconLp = LinearLayout.LayoutParams(dpToPx(20), dpToPx(20))
        iconLp.gravity = Gravity.CENTER_HORIZONTAL
        container.addView(icon, iconLp)

        val text = TextView(this)
        text.text = label
        text.textSize = 8f
        text.gravity = Gravity.CENTER
        text.setTextColor(Color.parseColor("#9E9E9E"))
        container.addView(text, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        return container
    }

    private fun makeSizeButton(label: String, strokeSize: Float): TextView {
        val btn = TextView(this)
        btn.text = label
        btn.textSize = 11f
        btn.gravity = Gravity.CENTER
        btn.setOnClickListener {
            currentStrokeWidth = strokeSize
            drawingViews.forEach { it.setStrokeWidth(strokeSize) }
            updateSizeButtons(label)
        }
        return btn
    }

    private fun updateSizeButtons(activeLabel: String) {
        listOf(sizeSmallBtn to "S", sizeMediumBtn to "M", sizeLargeBtn to "L").forEach { (btn, lbl) ->
            if (lbl == activeLabel) {
                btn.setBackgroundColor(Color.parseColor("#009688"))
                btn.setTextColor(Color.WHITE)
            } else {
                btn.setBackgroundColor(Color.TRANSPARENT)
                btn.setTextColor(Color.parseColor("#009688"))
            }
        }
    }

    private fun toggleMode(mode: AnnotationMode) {
        annotationMode = if (annotationMode == mode) AnnotationMode.NONE else mode
        scrollView.scrollingEnabled = annotationMode == AnnotationMode.NONE || annotationMode == AnnotationMode.IMAGE
        val isDrawing = annotationMode == AnnotationMode.DRAW
        val isErasing = annotationMode == AnnotationMode.ERASE
        val isHighlighting = annotationMode == AnnotationMode.HIGHLIGHT
        val isImageMode = annotationMode == AnnotationMode.IMAGE

        drawingViews.forEach { dv ->
            dv.isEnabled = isDrawing || isErasing || isHighlighting || isImageMode
            dv.setEraserMode(isErasing)
            dv.setHighlightMode(isHighlighting)
            if (isHighlighting) dv.setHighlightColor(currentHighlightColor)
            if (!isImageMode) {
                dv.pendingImageBitmap = null
                dv.isImagePlacementMode = false
            }
        }
        currentEraserMode = isErasing

        updateToolButtonState(drawBtn, isDrawing, Color.parseColor("#2196F3"))
        updateToolButtonState(highlightBtn, isHighlighting, Color.parseColor("#FFC107"))
        updateToolButtonState(eraserBtn, isErasing, Color.parseColor("#FF5722"))
        imageBtn?.let { updateToolButtonState(it, isImageMode, Color.parseColor("#4CAF50")) }
        updateColorSwatch()

        if (isImageMode) {
            if (availableImages.size == 1) activateImagePlacement(availableImages[0])
            else showImagePickerSheet()
        }
    }

    private fun activateImagePlacement(bitmap: Bitmap) {
        scrollView.scrollingEnabled = false
        drawingViews.forEach { dv ->
            dv.isEnabled = true
            dv.pendingImageBitmap = bitmap
            dv.isImagePlacementMode = true
        }
    }

    private fun clearPendingImageOnAllViews() {
        drawingViews.forEach { dv ->
            dv.pendingImageBitmap = null
            dv.isImagePlacementMode = false
        }
        scrollView.scrollingEnabled = false
    }

    private fun showImagePickerSheet() {
        val dialog = BottomSheetDialog(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
        }

        val titleTv = TextView(this).apply {
            text = "Select Image to Insert"
            textSize = 16f
            setTextColor(Color.BLACK)
            gravity = Gravity.CENTER
        }
        root.addView(titleTv, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dpToPx(12) })

        val scroll = HorizontalScrollView(this)
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        var selectedBitmap: Bitmap? = null

        val thumbSize = dpToPx(80)
        availableImages.forEachIndexed { idx, bmp ->
            val iv = ImageView(this).apply {
                setImageBitmap(bmp)
                scaleType = ImageView.ScaleType.CENTER_CROP
                val bg = GradientDrawable().apply {
                    cornerRadius = dpToPx(8).toFloat()
                    setColor(Color.parseColor("#F5F5F5"))
                }
                background = bg
                clipToOutline = true
                setOnClickListener { selectedBitmap = availableImages[idx]; dialog.dismiss() }
            }
            row.addView(iv, LinearLayout.LayoutParams(thumbSize, thumbSize).apply { marginEnd = dpToPx(8) })
        }
        scroll.addView(row)
        root.addView(scroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dpToPx(12) })

        val cancelTv = TextView(this).apply {
            text = "Cancel"
            textSize = 14f
            setTextColor(Color.parseColor("#2196F3"))
            gravity = Gravity.CENTER
            setOnClickListener { dialog.dismiss() }
        }
        root.addView(cancelTv, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        dialog.setOnDismissListener {
            val bmp = selectedBitmap
            if (bmp != null) {
                activateImagePlacement(bmp)
            } else {
                annotationMode = AnnotationMode.NONE
                scrollView.scrollingEnabled = true
                drawingViews.forEach { it.isEnabled = false }
                imageBtn?.let { updateToolButtonState(it, false, Color.parseColor("#4CAF50")) }
            }
        }

        dialog.setContentView(root)
        dialog.show()
    }

    private fun updateToolButtonState(container: LinearLayout, active: Boolean, activeColor: Int) {
        val iconView = container.getChildAt(0) as? ImageView
        val labelView = container.getChildAt(1) as? TextView
        if (active) {
            val bg = GradientDrawable()
            bg.cornerRadius = dpToPx(8).toFloat()
            bg.setColor(Color.argb(31, Color.red(activeColor), Color.green(activeColor), Color.blue(activeColor)))
            container.background = bg
            iconView?.setColorFilter(activeColor)
            labelView?.setTextColor(activeColor)
        } else {
            container.background = null
            iconView?.setColorFilter(Color.parseColor("#9E9E9E"))
            labelView?.setTextColor(Color.parseColor("#9E9E9E"))
        }
    }

    private fun updateColorSwatch() {
        val color = if (annotationMode == AnnotationMode.HIGHLIGHT) currentHighlightColor else currentColor
        (colorSwatch.background as? GradientDrawable)?.setColor(color)
    }

    private fun openAndRenderPdf(filePath: String) {
        try {
            val file = File(filePath)
            if (!file.exists()) throw FileNotFoundException("File not found: $filePath")
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            pdfRenderer = PdfRenderer(descriptor)
            pageCount = pdfRenderer!!.pageCount
            for (i in 0 until pageCount) addPageView(i)
        } catch (e: Exception) {
            finishWithError("Error opening PDF: ${e.message}")
        }
    }

    private fun addPageView(pageIndex: Int) {
        val renderer = pdfRenderer ?: return
        renderer.openPage(pageIndex).use { page ->
            val displayWidth = resources.displayMetrics.widthPixels
            val frameHeight = (displayWidth.toFloat() * page.height / page.width).toInt()

            val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            val frameLayout = FrameLayout(this)
            pdfContainer.addView(
                frameLayout,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, frameHeight)
                    .apply { bottomMargin = 8 }
            )

            val imageView = ImageView(this).apply {
                setImageBitmap(bitmap)
                scaleType = ImageView.ScaleType.FIT_CENTER
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }

            val drawingView = DrawingView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                isEnabled = false
                setColor(currentColor)
                setStrokeWidth(currentStrokeWidth)
                setEraserMode(currentEraserMode)
                setHighlightColor(currentHighlightColor)
                pageBitmapWidth = page.width.toFloat()
                pageBitmapHeight = page.height.toFloat()
                onStrokeAdded = { undoStack.add(pageIndex) }
                onImagePlaced = { clearPendingImageOnAllViews() }
            }

            drawingViews.add(drawingView)
            frameLayout.addView(imageView)
            frameLayout.addView(drawingView)

            // Use explicit reference to avoid 'this' ambiguity inside nested lambda
            drawingView.onImageSelectionChanged = { selected ->
                if (selected) showImageActions(drawingView)
                else if (activeImageView == drawingView) hideImageActions()
            }

            imageView.post {
                drawingView.setTransformMatrix(imageView.imageMatrix)
            }
        }
    }

    private fun showColorPicker() {
        val colorPicker = ColorPickerDialog(this)
        colorPicker.setOnColorSelectedListener { color ->
            if (annotationMode == AnnotationMode.HIGHLIGHT) {
                val c = Color.argb(128, Color.red(color), Color.green(color), Color.blue(color))
                currentHighlightColor = c
                drawingViews.forEach { it.setHighlightColor(c) }
            } else {
                currentColor = color
                drawingViews.forEach { it.setColor(color) }
            }
            updateColorSwatch()
        }
        colorPicker.show()
    }

    private fun buildAnnotatedPdf(): ByteArray? {
        return try {
            val document = PdfDocument()
            val renderer = pdfRenderer ?: return null

            for (i in 0 until pageCount) {
                renderer.openPage(i).use { page ->
                    val pageInfo = PdfDocument.PageInfo.Builder(page.width, page.height, i).create()
                    val documentPage = document.startPage(pageInfo)

                    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    documentPage.canvas.drawBitmap(bitmap, 0f, 0f, null)
                    bitmap.recycle()

                    drawingViews.getOrNull(i)?.getHighlights()?.forEach { h ->
                        documentPage.canvas.drawRect(h.rect, Paint().apply { color = h.color; style = Paint.Style.FILL })
                    }

                    drawingViews.getOrNull(i)?.getImageAnnotations()?.forEach { img ->
                        documentPage.canvas.drawBitmap(img.bitmap, null, img.rect, null)
                    }

                    drawingViews.getOrNull(i)?.getAnnotations()?.forEach { a ->
                        documentPage.canvas.drawPath(a.path, Paint().apply {
                            color = a.color; strokeWidth = a.strokeWidth
                            style = Paint.Style.STROKE
                            strokeJoin = Paint.Join.ROUND; strokeCap = Paint.Cap.ROUND
                            isAntiAlias = true
                        })
                    }

                    document.finishPage(documentPage)
                }
            }

            val out = ByteArrayOutputStream()
            document.writeTo(out)
            document.close()
            out.toByteArray()
        } catch (e: Exception) { null }
    }

    private fun saveAndFinish() {
        val savePath = intent.getStringExtra("savePath")
        if (savePath.isNullOrBlank()) {
            Toast.makeText(this, "Error: Save path not provided", Toast.LENGTH_LONG).show()
            FlutterPdfAnnotationsPlugin.notifySaveResult(null)
            finish(); return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val pdfBytes = buildAnnotatedPdf()
            withContext(Dispatchers.Main) {
                if (pdfBytes == null) {
                    Toast.makeText(this@PDFViewerActivity, "Error building PDF", Toast.LENGTH_LONG).show()
                    FlutterPdfAnnotationsPlugin.notifySaveResult(null); finish(); return@withContext
                }
                try {
                    val outputFile = File(savePath).absoluteFile
                    outputFile.parentFile?.mkdirs()
                    withContext(Dispatchers.IO) { FileOutputStream(outputFile).use { it.write(pdfBytes) } }
                    Toast.makeText(this@PDFViewerActivity, "PDF saved!", Toast.LENGTH_SHORT).show()
                    FlutterPdfAnnotationsPlugin.notifySaveResult(outputFile.absolutePath)
                } catch (e: Exception) {
                    Toast.makeText(this@PDFViewerActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
                    FlutterPdfAnnotationsPlugin.notifySaveResult(null)
                }
                finish()
            }
        }
    }

    private fun shareAndSave() {
        CoroutineScope(Dispatchers.IO).launch {
            val pdfBytes = buildAnnotatedPdf()
            withContext(Dispatchers.Main) {
                if (pdfBytes == null) {
                    Toast.makeText(this@PDFViewerActivity, "Error preparing PDF for sharing", Toast.LENGTH_LONG).show()
                    return@withContext
                }
                try {
                    val tempFile = File(cacheDir, "share_${System.currentTimeMillis()}.pdf")
                    withContext(Dispatchers.IO) { FileOutputStream(tempFile).use { it.write(pdfBytes) } }
                    val uri = FileProvider.getUriForFile(
                        this@PDFViewerActivity,
                        "${packageName}.flutter_pdf_annotations.provider",
                        tempFile
                    )
                    startActivity(Intent.createChooser(
                        Intent(Intent.ACTION_SEND).apply {
                            type = "application/pdf"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, "Share PDF"
                    ))
                } catch (e: Exception) {
                    Toast.makeText(this@PDFViewerActivity, "Error sharing PDF: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun finishWithError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        pdfRenderer?.close()
    }
}

private class LockableScrollView(context: Context) : ScrollView(context) {
    var scrollingEnabled = true
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean =
        if (scrollingEnabled) super.onInterceptTouchEvent(ev) else false
    override fun onTouchEvent(ev: MotionEvent): Boolean =
        if (scrollingEnabled) super.onTouchEvent(ev) else false
}
