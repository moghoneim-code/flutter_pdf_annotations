package com.ghoneim.flutter_pdf_annotations

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.TypedValue
import android.view.*
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import java.io.*
import kotlinx.coroutines.*

class PDFViewerActivity : AppCompatActivity() {

    companion object {
        private const val MAX_RENDER_DENSITY = 3f
        private const val MAX_IMAGE_FILE_SIZE = 10 * 1024 * 1024L // 10 MB
        private const val MAX_IMAGE_DIMENSION = 2048
        private const val IMAGE_PLACEMENT_REQUEST = 1001
    }

    private var pdfRenderer: PdfRenderer? = null
    private var pageCount = 0
    private lateinit var scrollView: LockableScrollView
    private lateinit var pdfContainer: LinearLayout
    private val drawingViews = mutableListOf<DrawingView>()
    private val pageBitmaps = mutableListOf<Bitmap>()
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

    // Bottom bar
    private lateinit var normalBarContent: LinearLayout
    private lateinit var optionsPanel: LinearLayout
    private lateinit var optionsSeparator: View

    // Progress overlay for save
    private var progressOverlay: FrameLayout? = null

    // Ensures Flutter is notified exactly once per session.
    private var resultReported = false

    private fun reportSuccess(path: String) {
        if (resultReported) return
        resultReported = true
        FlutterPdfAnnotationsPlugin.notifySaveResult(path)
    }

    private fun reportCancelled() {
        if (resultReported) return
        resultReported = true
        FlutterPdfAnnotationsPlugin.notifyCancelled()
    }

    private fun reportError(message: String) {
        if (resultReported) return
        resultReported = true
        FlutterPdfAnnotationsPlugin.notifySaveError(message)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        originalPdfPath = intent?.getStringExtra("filePath")
            ?: run { finishWithError("Missing file path"); return }

        applyIntentConfig()

        val topBarHeight = dpToPx(52)
        val bottomBarHeight = dpToPx(60)

        val mainLayout = FrameLayout(this)
        mainLayout.setBackgroundColor(Color.parseColor("#F5F5F5"))

        scrollView = LockableScrollView(this)
        scrollView.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        scrollView.setBackgroundColor(Color.parseColor("#EEEEEE"))

        pdfContainer = LinearLayout(this)
        pdfContainer.orientation = LinearLayout.VERTICAL
        pdfContainer.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        pdfContainer.setPadding(0, topBarHeight, 0, bottomBarHeight)
        scrollView.addView(pdfContainer)

        val title = intent.getStringExtra("title") ?: FPAStrings.defaultTitle
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

        // Scroll to initial page if specified
        val initialPage = intent.getIntExtra("initialPage", 0)
        if (initialPage > 0 && initialPage < pageCount) {
            scrollView.post {
                val targetView = pdfContainer.getChildAt(initialPage)
                if (targetView != null) {
                    scrollView.scrollTo(0, targetView.top)
                }
            }
        }
    }

    private fun applyIntentConfig() {
        FPAStrings.configure(intent.getStringExtra("locale"))
        if (intent.hasExtra("initialPenColor"))
            currentColor = intent.getIntExtra("initialPenColor", currentColor)
        if (intent.hasExtra("initialHighlightColor"))
            currentHighlightColor = intent.getIntExtra("initialHighlightColor", currentHighlightColor)
        if (intent.hasExtra("initialStrokeWidth"))
            currentStrokeWidth = intent.getFloatExtra("initialStrokeWidth", currentStrokeWidth)

        intent.getStringArrayListExtra("imagePaths")?.forEach { path ->
            try {
                val file = File(path)
                if (!file.exists()) {
                    android.util.Log.e("PDFViewerActivity", "Image not found: $path")
                    return@forEach
                }
                if (file.length() > MAX_IMAGE_FILE_SIZE) {
                    android.util.Log.e("PDFViewerActivity", "Image too large (>10MB): $path")
                    return@forEach
                }
                // Two-pass decode: first get dimensions, then decode with inSampleSize
                val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, boundsOpts)
                val longestEdge = maxOf(boundsOpts.outWidth, boundsOpts.outHeight)
                val sampleSize = if (longestEdge > MAX_IMAGE_DIMENSION) {
                    (longestEdge / MAX_IMAGE_DIMENSION).coerceAtLeast(1)
                } else 1

                val opts = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                    inSampleSize = sampleSize
                }
                var bmp = BitmapFactory.decodeFile(path, opts)
                if (bmp != null) {
                    bmp = downscaleIfNeeded(bmp)
                    availableImages.add(bmp)
                } else {
                    android.util.Log.e("PDFViewerActivity", "Failed to decode image: $path")
                }
            } catch (e: Exception) {
                android.util.Log.e("PDFViewerActivity", "Error loading image: $path", e)
            }
        }
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()

    /** Downscale a bitmap if its longest edge exceeds MAX_IMAGE_DIMENSION to prevent UI lag. */
    private fun downscaleIfNeeded(bitmap: Bitmap): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= MAX_IMAGE_DIMENSION) return bitmap
        val scale = MAX_IMAGE_DIMENSION.toFloat() / longest
        val newW = (bitmap.width * scale).toInt()
        val newH = (bitmap.height * scale).toInt()
        val scaled = Bitmap.createScaledBitmap(bitmap, newW, newH, true)
        if (scaled !== bitmap) bitmap.recycle()
        return scaled
    }




    private fun buildTopBar(title: String = "PDF Annotations"): LinearLayout {
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setBackgroundColor(Color.WHITE)
        bar.elevation = dpToPx(2).toFloat()
        bar.setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))

        val cancelBtn = Button(this)
        cancelBtn.text = FPAStrings.cancel
        cancelBtn.setTextColor(Color.parseColor("#2196F3"))
        cancelBtn.background = null
        cancelBtn.isAllCaps = false
        cancelBtn.setOnClickListener { reportCancelled(); finish() }
        bar.addView(cancelBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        val titleView = TextView(this)
        titleView.text = title
        titleView.textSize = 17f
        titleView.setTextColor(Color.parseColor("#212121"))
        titleView.gravity = Gravity.CENTER
        titleView.setTypeface(null, android.graphics.Typeface.BOLD)
        bar.addView(titleView, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val shareBtn = ImageButton(this)
        shareBtn.setImageResource(android.R.drawable.ic_menu_share)
        shareBtn.background = null
        shareBtn.setColorFilter(Color.parseColor("#2196F3"))
        shareBtn.setOnClickListener { shareAndSave() }
        val shareLp = LinearLayout.LayoutParams(dpToPx(44), dpToPx(44))
        shareLp.marginEnd = dpToPx(4)
        bar.addView(shareBtn, shareLp)

        val saveBtn = Button(this)
        saveBtn.text = FPAStrings.save
        saveBtn.setTextColor(Color.WHITE)
        saveBtn.isAllCaps = false
        saveBtn.setTypeface(null, android.graphics.Typeface.BOLD)
        val saveBg = GradientDrawable()
        saveBg.cornerRadius = dpToPx(8).toFloat()
        saveBg.setColor(Color.parseColor("#2196F3"))
        saveBtn.background = saveBg
        saveBtn.setPadding(dpToPx(16), dpToPx(4), dpToPx(16), dpToPx(4))
        saveBtn.setOnClickListener { saveAndFinish() }
        bar.addView(saveBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dpToPx(36)
        ))

        return bar
    }

    /**
     * Returns a FrameLayout that contains three layers:
     *  - normalBarContent  : vertical layout with optional options panel + tool row
     *  - imageActionContent: Apply / Delete buttons (gone by default, shown when image selected)
     */
    private fun buildBottomBar(): FrameLayout {
        val container = FrameLayout(this)
        container.setBackgroundColor(Color.WHITE)
        container.elevation = dpToPx(4).toFloat()

        // ── Normal content (options panel + tool row) ────────────────────────
        normalBarContent = LinearLayout(this)
        normalBarContent.orientation = LinearLayout.VERTICAL

        // ── Options panel (color + size, shown when Draw/Highlight active) ──
        optionsPanel = LinearLayout(this)
        optionsPanel.orientation = LinearLayout.HORIZONTAL
        optionsPanel.gravity = Gravity.CENTER_VERTICAL
        optionsPanel.setPadding(dpToPx(16), dpToPx(6), dpToPx(16), dpToPx(6))
        optionsPanel.visibility = View.GONE

        // Color swatch (enlarged 40dp)
        colorSwatch = View(this)
        val swatchSize = dpToPx(40)
        val swatchBg = GradientDrawable()
        swatchBg.shape = GradientDrawable.OVAL
        swatchBg.setColor(currentColor)
        swatchBg.setStroke(dpToPx(2), Color.parseColor("#BDBDBD"))
        colorSwatch.background = swatchBg
        colorSwatch.isClickable = true
        colorSwatch.setOnClickListener { showColorPicker() }
        optionsPanel.addView(colorSwatch, LinearLayout.LayoutParams(swatchSize, swatchSize).apply {
            marginEnd = dpToPx(16)
        })

        // Size segmented control (S/M/L as a toggle group)
        val sizeContainer = LinearLayout(this)
        sizeContainer.orientation = LinearLayout.HORIZONTAL
        sizeContainer.gravity = Gravity.CENTER_VERTICAL
        val segBg = GradientDrawable()
        segBg.cornerRadius = dpToPx(8).toFloat()
        segBg.setStroke(dpToPx(1), Color.parseColor("#009688"))
        sizeContainer.background = segBg

        sizeSmallBtn = makeSizeButton("S", 3f)
        sizeMediumBtn = makeSizeButton("M", 8f)
        sizeLargeBtn = makeSizeButton("L", 18f)

        val segBtnLp = LinearLayout.LayoutParams(dpToPx(44), dpToPx(36))
        sizeContainer.addView(sizeSmallBtn, segBtnLp)
        sizeContainer.addView(sizeMediumBtn, LinearLayout.LayoutParams(dpToPx(44), dpToPx(36)))
        sizeContainer.addView(sizeLargeBtn, LinearLayout.LayoutParams(dpToPx(44), dpToPx(36)))
        optionsPanel.addView(sizeContainer, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        updateSizeButtons(when {
            currentStrokeWidth <= 4f -> "S"
            currentStrokeWidth >= 14f -> "L"
            else -> "M"
        })

        // Options separator line
        optionsSeparator = View(this)
        optionsSeparator.setBackgroundColor(Color.parseColor("#E0E0E0"))
        optionsSeparator.visibility = View.GONE
        normalBarContent.addView(optionsPanel, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        normalBarContent.addView(optionsSeparator, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dpToPx(1)))

        // ── Primary tool row ─────────────────────────────────────────���───────
        val toolRow = LinearLayout(this)
        toolRow.orientation = LinearLayout.HORIZONTAL
        toolRow.gravity = Gravity.CENTER_VERTICAL
        toolRow.setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))

        drawBtn = makeToolButton(FPAStrings.draw, android.R.drawable.ic_menu_edit) { toggleMode(AnnotationMode.DRAW) }
        highlightBtn = makeToolButton(FPAStrings.mark, android.R.drawable.ic_menu_crop) { toggleMode(AnnotationMode.HIGHLIGHT) }
        eraserBtn = makeToolButton(FPAStrings.erase, android.R.drawable.ic_menu_close_clear_cancel) { toggleMode(AnnotationMode.ERASE) }

        toolRow.addView(drawBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        toolRow.addView(highlightBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        toolRow.addView(eraserBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        if (availableImages.isNotEmpty()) {
            val btn = makeToolButton(FPAStrings.image, android.R.drawable.ic_menu_gallery) { toggleMode(AnnotationMode.IMAGE) }
            imageBtn = btn
            toolRow.addView(btn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }

        // Vertical divider between tools and actions
        val divider = View(this)
        divider.setBackgroundColor(Color.parseColor("#E0E0E0"))
        toolRow.addView(divider, LinearLayout.LayoutParams(dpToPx(1), dpToPx(32)).apply {
            marginStart = dpToPx(4); marginEnd = dpToPx(4)
        })

        // Action buttons (undo, clear)
        val undoBtn = makeToolButton(FPAStrings.undo, android.R.drawable.ic_menu_revert) {
            if (undoStack.isNotEmpty()) {
                val pageIdx = undoStack.removeAt(undoStack.size - 1)
                drawingViews.getOrNull(pageIdx)?.undo()
            }
        }
        toolRow.addView(undoBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val clearBtn = makeToolButton(FPAStrings.clear, android.R.drawable.ic_menu_delete) {
            AlertDialog.Builder(this)
                .setTitle(FPAStrings.clearAllTitle)
                .setMessage(FPAStrings.clearAllMessage)
                .setPositiveButton(FPAStrings.clear) { _, _ -> drawingViews.forEach { it.clearAnnotations() }; undoStack.clear() }
                .setNegativeButton(FPAStrings.cancel, null)
                .show()
        }
        toolRow.addView(clearBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        normalBarContent.addView(toolRow, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        container.addView(normalBarContent, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        return container
    }

    private fun makeToolButton(label: String, iconRes: Int, onClick: () -> Unit): LinearLayout {
        val container = LinearLayout(this)
        container.orientation = LinearLayout.VERTICAL
        container.gravity = Gravity.CENTER
        container.minimumWidth = dpToPx(48)
        container.minimumHeight = dpToPx(48)
        container.setPadding(dpToPx(2), dpToPx(4), dpToPx(2), dpToPx(2))
        container.setOnClickListener { onClick() }

        val icon = ImageView(this)
        icon.setImageResource(iconRes)
        icon.setColorFilter(Color.parseColor("#9E9E9E"))
        val iconLp = LinearLayout.LayoutParams(dpToPx(24), dpToPx(24))
        iconLp.gravity = Gravity.CENTER_HORIZONTAL
        container.addView(icon, iconLp)

        val text = TextView(this)
        text.text = label
        text.textSize = 9f
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
        val bg = GradientDrawable()
        bg.cornerRadius = dpToPx(6).toFloat()
        btn.background = bg
        btn.setOnClickListener {
            currentStrokeWidth = strokeSize
            drawingViews.forEach { it.setStrokeWidth(strokeSize) }
            updateSizeButtons(label)
        }
        return btn
    }

    private fun updateSizeButtons(activeLabel: String) {
        listOf(sizeSmallBtn to "S", sizeMediumBtn to "M", sizeLargeBtn to "L").forEach { (btn, lbl) ->
            val bg = btn.background as? GradientDrawable ?: GradientDrawable().also { btn.background = it }
            if (lbl == activeLabel) {
                bg.setColor(Color.parseColor("#009688"))
                btn.setTextColor(Color.WHITE)
            } else {
                bg.setColor(Color.TRANSPARENT)
                btn.setTextColor(Color.parseColor("#009688"))
            }
        }
    }

    private fun toggleMode(mode: AnnotationMode) {
        // Image mode opens a dedicated screen
        if (mode == AnnotationMode.IMAGE) {
            openImagePlacementScreen()
            return
        }

        annotationMode = if (annotationMode == mode) AnnotationMode.NONE else mode
        scrollView.scrollingEnabled = annotationMode == AnnotationMode.NONE
        val isDrawing = annotationMode == AnnotationMode.DRAW
        val isErasing = annotationMode == AnnotationMode.ERASE
        val isHighlighting = annotationMode == AnnotationMode.HIGHLIGHT

        drawingViews.forEach { dv ->
            dv.isEnabled = isDrawing || isErasing || isHighlighting
            dv.setEraserMode(isErasing)
            dv.setHighlightMode(isHighlighting)
            if (isHighlighting) dv.setHighlightColor(currentHighlightColor)
        }
        currentEraserMode = isErasing

        updateToolButtonState(drawBtn, isDrawing, Color.parseColor("#2196F3"))
        updateToolButtonState(highlightBtn, isHighlighting, Color.parseColor("#FFC107"))
        updateToolButtonState(eraserBtn, isErasing, Color.parseColor("#FF5722"))
        imageBtn?.let { updateToolButtonState(it, false, Color.parseColor("#4CAF50")) }
        updateColorSwatch()

        // Show/hide options panel for draw and highlight modes
        if (isDrawing || isHighlighting) showOptionsPanel() else hideOptionsPanel()
    }

    private fun openImagePlacementScreen() {
        ImagePlacementData.availableImages = availableImages
        ImagePlacementData.results.clear()
        val intent = Intent(this, ImagePlacementActivity::class.java)
        intent.putExtra("filePath", originalPdfPath)
        // Find current visible page based on scroll position
        val scrollY = scrollView.scrollY
        var visiblePage = 0
        for (i in 0 until pdfContainer.childCount) {
            val child = pdfContainer.getChildAt(i)
            if (child.top + child.height / 2 > scrollY) { visiblePage = i; break }
        }
        intent.putExtra("initialPage", visiblePage)
        getIntent().getStringExtra("locale")?.let { intent.putExtra("locale", it) }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, IMAGE_PLACEMENT_REQUEST)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == IMAGE_PLACEMENT_REQUEST && resultCode == RESULT_OK) {
            val results = ImagePlacementData.results
            for (p in results) {
                val bmp = ImagePlacementData.availableImages.getOrNull(p.imageIndex) ?: continue
                val dv = drawingViews.getOrNull(p.pageIndex) ?: continue
                dv.addConfirmedImage(bmp, p.rect)
                undoStack.add(p.pageIndex)
            }
            ImagePlacementData.results.clear()
        }
    }

    private fun showOptionsPanel() {
        if (optionsPanel.visibility == View.VISIBLE) return
        optionsPanel.visibility = View.VISIBLE
        optionsSeparator.visibility = View.VISIBLE
        optionsPanel.alpha = 0f
        optionsPanel.animate().alpha(1f).setDuration(200).start()
    }

    private fun hideOptionsPanel() {
        if (optionsPanel.visibility != View.VISIBLE) return
        optionsPanel.animate().alpha(0f).setDuration(150).withEndAction {
            optionsPanel.visibility = View.GONE
            optionsSeparator.visibility = View.GONE
        }.start()
    }




    private fun updateToolButtonState(container: LinearLayout, active: Boolean, activeColor: Int) {
        val iconView = container.getChildAt(0) as? ImageView
        val labelView = container.getChildAt(1) as? TextView
        if (active) {
            val bg = GradientDrawable()
            bg.cornerRadius = dpToPx(8).toFloat()
            bg.setColor(Color.argb(25, Color.red(activeColor), Color.green(activeColor), Color.blue(activeColor)))
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
            try {
                pdfRenderer = PdfRenderer(descriptor)
            } catch (e: Exception) {
                descriptor.close()
                throw e
            }
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

            // Render at display density for sharp output (capped to avoid excessive memory)
            val density = resources.displayMetrics.density.coerceAtMost(MAX_RENDER_DENSITY)
            val renderWidth = (page.width * density).toInt()
            val renderHeight = (page.height * density).toInt()

            val bitmap = Bitmap.createBitmap(renderWidth, renderHeight, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            val frameLayout = FrameLayout(this)
            pdfContainer.addView(
                frameLayout,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, frameHeight)
                    .apply { bottomMargin = dpToPx(4) }
            )

            pageBitmaps.add(bitmap)
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
            }

            drawingViews.add(drawingView)
            frameLayout.addView(imageView)
            frameLayout.addView(drawingView)

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
        val renderer = pdfRenderer ?: return null
        val document = PdfDocument()
        return try {
            for (i in 0 until pageCount) {
                renderer.openPage(i).use { page ->
                    val pageInfo = PdfDocument.PageInfo.Builder(page.width, page.height, i).create()
                    val documentPage = document.startPage(pageInfo)

                    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    documentPage.canvas.drawBitmap(bitmap, 0f, 0f, null)
                    bitmap.recycle()

                    drawingViews.getOrNull(i)?.getHighlights()?.forEach { h ->
                        documentPage.canvas.drawRect(h.rect, Paint().apply { color = h.color; style = Paint.Style.FILL })
                    }

                    drawingViews.getOrNull(i)?.getImageAnnotations()?.forEach { img ->
                        documentPage.canvas.drawBitmap(img.bitmap, null, img.rect, Paint().apply { isFilterBitmap = true })
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
            out.toByteArray()
        } catch (e: Exception) {
            null
        } finally {
            document.close()
        }
    }

    private fun saveAndFinish() {
        val savePath = intent.getStringExtra("savePath")
        if (savePath.isNullOrBlank()) {
            finishWithError("Save path not provided")
            return
        }

        // Show progress indicator
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(Color.argb(120, 255, 255, 255))
            isClickable = true  // block touches
        }
        val progress = ProgressBar(this)
        val progressLp = FrameLayout.LayoutParams(dpToPx(48), dpToPx(48))
        progressLp.gravity = Gravity.CENTER
        overlay.addView(progress, progressLp)
        val label = TextView(this).apply {
            text = FPAStrings.saving
            setTextColor(Color.parseColor("#424242"))
            textSize = 14f
            gravity = Gravity.CENTER
        }
        val labelLp = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        labelLp.gravity = Gravity.CENTER
        labelLp.topMargin = dpToPx(56)
        overlay.addView(label, labelLp)
        (window.decorView as? ViewGroup)?.addView(overlay)
        progressOverlay = overlay

        lifecycleScope.launch {
            val pdfBytes = withContext(Dispatchers.IO) { buildAnnotatedPdf() }
            progressOverlay?.let { (window.decorView as? ViewGroup)?.removeView(it) }
            if (pdfBytes == null) {
                Toast.makeText(this@PDFViewerActivity, FPAStrings.errorBuildingPDF, Toast.LENGTH_LONG).show()
                reportError("Failed to build annotated PDF"); finish(); return@launch
            }
            try {
                val outputFile = File(savePath).canonicalFile
                val allowedDir = (getExternalFilesDir(null) ?: filesDir).canonicalPath
                if (!outputFile.path.startsWith(allowedDir + File.separator) &&
                    !outputFile.path.startsWith(filesDir.canonicalPath + File.separator)) {
                    Toast.makeText(this@PDFViewerActivity, "Error: Invalid save path", Toast.LENGTH_LONG).show()
                    reportError("Save path outside allowed directory"); finish(); return@launch
                }
                outputFile.parentFile?.mkdirs()
                withContext(Dispatchers.IO) { FileOutputStream(outputFile).use { it.write(pdfBytes) } }
                Toast.makeText(this@PDFViewerActivity, FPAStrings.pdfSaved, Toast.LENGTH_SHORT).show()
                reportSuccess(outputFile.absolutePath)
            } catch (e: Exception) {
                Toast.makeText(this@PDFViewerActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
                reportError("Failed to write PDF: ${e.message ?: e.toString()}")
            }
            finish()
        }
    }

    private fun shareAndSave() {
        lifecycleScope.launch {
            val pdfBytes = withContext(Dispatchers.IO) { buildAnnotatedPdf() }
            if (pdfBytes == null) {
                Toast.makeText(this@PDFViewerActivity, "Error preparing PDF for sharing", Toast.LENGTH_LONG).show()
                return@launch
            }
            run {
                try {
                    val tempFile = File(cacheDir, "share_${System.currentTimeMillis()}.pdf")
                    withContext(Dispatchers.IO) { FileOutputStream(tempFile).use { it.write(pdfBytes) } }
                    val uri = FileProvider.getUriForFile(
                        this@PDFViewerActivity,
                        "${packageName}.flutter_pdf_annotations.provider",
                        tempFile
                    )
                    // Schedule temp file deletion after the share sheet is dismissed
                    tempFile.deleteOnExit()
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
        reportError(message)
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        // If the activity is destroyed without explicitly reporting a result
        // (back gesture, system kill, config change), notify Flutter so the
        // Dart completer is not left hanging.
        reportCancelled()
        pdfRenderer?.close()
        pageBitmaps.forEach { if (!it.isRecycled) it.recycle() }
        pageBitmaps.clear()
    }
}

private class LockableScrollView(context: Context) : ScrollView(context) {
    var scrollingEnabled = true
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean =
        if (scrollingEnabled) super.onInterceptTouchEvent(ev) else false
    override fun onTouchEvent(ev: MotionEvent): Boolean =
        if (scrollingEnabled) super.onTouchEvent(ev) else false
}
