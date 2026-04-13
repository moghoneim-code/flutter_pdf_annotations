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
import android.util.TypedValue
import android.view.*
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.google.android.material.bottomsheet.BottomSheetDialog
import java.io.*
import kotlinx.coroutines.*

class PDFViewerActivity : AppCompatActivity() {

    companion object {
        private const val MAX_RENDER_DENSITY = 3f
        private const val MAX_IMAGE_FILE_SIZE = 10 * 1024 * 1024L // 10 MB
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

    // Bottom bar: swaps between normal tools and image-action buttons
    private lateinit var normalBarContent: LinearLayout
    private lateinit var imageActionContent: LinearLayout
    private var activeImageView: DrawingView? = null

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
        val bottomBarHeight = dpToPx(64)

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
                val file = File(path)
                if (!file.exists()) {
                    android.util.Log.e("PDFViewerActivity", "Image not found: $path")
                    return@forEach
                }
                if (file.length() > MAX_IMAGE_FILE_SIZE) {
                    android.util.Log.e("PDFViewerActivity", "Image too large (>10MB): $path")
                    return@forEach
                }
                val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
                val bmp = BitmapFactory.decodeFile(path, opts)
                if (bmp != null) availableImages.add(bmp)
                else android.util.Log.e("PDFViewerActivity", "Failed to decode image: $path")
            } catch (e: Exception) {
                android.util.Log.e("PDFViewerActivity", "Error loading image: $path", e)
            }
        }
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()

    /** Show Apply/Delete bar; hide normal tools. */
    private fun showImageActions(dv: DrawingView) {
        activeImageView = dv
        normalBarContent.animate().alpha(0f).setDuration(150).withEndAction {
            normalBarContent.visibility = View.GONE
            imageActionContent.visibility = View.VISIBLE
            imageActionContent.alpha = 0f
            imageActionContent.animate().alpha(1f).setDuration(150).start()
        }.start()
    }

    /** Restore normal tools bar. */
    private fun hideImageActions() {
        activeImageView = null
        imageActionContent.animate().alpha(0f).setDuration(150).withEndAction {
            imageActionContent.visibility = View.GONE
            normalBarContent.visibility = View.VISIBLE
            normalBarContent.alpha = 0f
            normalBarContent.animate().alpha(1f).setDuration(150).start()
        }.start()
    }

    private fun buildTopBar(title: String = "PDF Annotations"): LinearLayout {
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setBackgroundColor(Color.WHITE)
        bar.elevation = dpToPx(2).toFloat()
        bar.setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))

        val cancelBtn = Button(this)
        cancelBtn.text = "Cancel"
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
        container.elevation = dpToPx(4).toFloat()

        // ── Normal tools ──────────────────────────────────────────────────────
        normalBarContent = LinearLayout(this)
        normalBarContent.orientation = LinearLayout.HORIZONTAL
        normalBarContent.gravity = Gravity.CENTER_VERTICAL
        normalBarContent.setPadding(dpToPx(4), dpToPx(6), dpToPx(4), dpToPx(6))

        // Row 1: annotation tools
        val toolsRow = LinearLayout(this)
        toolsRow.orientation = LinearLayout.HORIZONTAL
        toolsRow.gravity = Gravity.CENTER_VERTICAL

        drawBtn = makeToolButton("Draw", android.R.drawable.ic_menu_edit) { toggleMode(AnnotationMode.DRAW) }
        highlightBtn = makeToolButton("Mark", android.R.drawable.ic_menu_crop) { toggleMode(AnnotationMode.HIGHLIGHT) }
        eraserBtn = makeToolButton("Erase", android.R.drawable.ic_menu_close_clear_cancel) { toggleMode(AnnotationMode.ERASE) }

        toolsRow.addView(drawBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        toolsRow.addView(highlightBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        toolsRow.addView(eraserBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        if (availableImages.isNotEmpty()) {
            val btn = makeToolButton("Image", android.R.drawable.ic_menu_gallery) { toggleMode(AnnotationMode.IMAGE) }
            imageBtn = btn
            toolsRow.addView(btn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }

        normalBarContent.addView(toolsRow, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 3f))

        // Separator
        val sep1 = View(this)
        sep1.setBackgroundColor(Color.parseColor("#E0E0E0"))
        normalBarContent.addView(sep1, LinearLayout.LayoutParams(dpToPx(1), dpToPx(32)).apply {
            marginStart = dpToPx(4); marginEnd = dpToPx(4)
        })

        // Color swatch
        colorSwatch = View(this)
        val swatchSize = dpToPx(32)
        val swatchLp = LinearLayout.LayoutParams(swatchSize, swatchSize)
        swatchLp.gravity = Gravity.CENTER_VERTICAL
        swatchLp.marginStart = dpToPx(2)
        swatchLp.marginEnd = dpToPx(2)
        colorSwatch.layoutParams = swatchLp
        val swatchBg = GradientDrawable()
        swatchBg.shape = GradientDrawable.OVAL
        swatchBg.setColor(currentColor)
        swatchBg.setStroke(dpToPx(2), Color.parseColor("#BDBDBD"))
        colorSwatch.background = swatchBg
        colorSwatch.isClickable = true
        colorSwatch.setOnClickListener { showColorPicker() }
        normalBarContent.addView(colorSwatch)

        // Size buttons
        val sizeContainer = LinearLayout(this)
        sizeContainer.orientation = LinearLayout.HORIZONTAL
        sizeContainer.gravity = Gravity.CENTER_VERTICAL
        sizeSmallBtn = makeSizeButton("S", 3f)
        sizeMediumBtn = makeSizeButton("M", 8f)
        sizeLargeBtn = makeSizeButton("L", 18f)
        sizeContainer.addView(sizeSmallBtn, LinearLayout.LayoutParams(dpToPx(28), dpToPx(28)).apply { marginEnd = dpToPx(2) })
        sizeContainer.addView(sizeMediumBtn, LinearLayout.LayoutParams(dpToPx(28), dpToPx(28)).apply { marginEnd = dpToPx(2) })
        sizeContainer.addView(sizeLargeBtn, LinearLayout.LayoutParams(dpToPx(28), dpToPx(28)))
        normalBarContent.addView(sizeContainer, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            marginStart = dpToPx(2); marginEnd = dpToPx(2)
        })

        updateSizeButtons(when {
            currentStrokeWidth <= 4f -> "S"
            currentStrokeWidth >= 14f -> "L"
            else -> "M"
        })

        // Separator
        val sep2 = View(this)
        sep2.setBackgroundColor(Color.parseColor("#E0E0E0"))
        normalBarContent.addView(sep2, LinearLayout.LayoutParams(dpToPx(1), dpToPx(32)).apply {
            marginStart = dpToPx(2); marginEnd = dpToPx(4)
        })

        // Action buttons (undo, clear, save)
        val actionsRow = LinearLayout(this)
        actionsRow.orientation = LinearLayout.HORIZONTAL
        actionsRow.gravity = Gravity.CENTER_VERTICAL

        val undoBtn = makeToolButton("Undo", android.R.drawable.ic_menu_revert) {
            if (undoStack.isNotEmpty()) {
                val pageIdx = undoStack.removeAt(undoStack.size - 1)
                drawingViews.getOrNull(pageIdx)?.undo()
            }
        }
        actionsRow.addView(undoBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val clearBtn = makeToolButton("Clear", android.R.drawable.ic_menu_delete) {
            AlertDialog.Builder(this)
                .setTitle("Clear All?")
                .setMessage("This will remove all annotations.")
                .setPositiveButton("Clear") { _, _ -> drawingViews.forEach { it.clearAnnotations() }; undoStack.clear() }
                .setNegativeButton("Cancel", null)
                .show()
        }
        actionsRow.addView(clearBtn, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        normalBarContent.addView(actionsRow, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f))

        // Save button
        val saveBtn = Button(this)
        saveBtn.text = "Save"
        saveBtn.setTextColor(Color.WHITE)
        saveBtn.isAllCaps = false
        val saveBg = GradientDrawable()
        saveBg.cornerRadius = dpToPx(8).toFloat()
        saveBg.setColor(Color.parseColor("#2196F3"))
        saveBtn.background = saveBg
        saveBtn.setPadding(dpToPx(12), dpToPx(4), dpToPx(12), dpToPx(4))
        saveBtn.setOnClickListener { saveAndFinish() }
        normalBarContent.addView(saveBtn, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dpToPx(40)).apply {
            marginStart = dpToPx(4); marginEnd = dpToPx(2)
        })

        container.addView(normalBarContent, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // ── Image action toolbar ───────────────────────────��────────────────
        imageActionContent = LinearLayout(this)
        imageActionContent.orientation = LinearLayout.VERTICAL
        imageActionContent.gravity = Gravity.CENTER_HORIZONTAL
        imageActionContent.setPadding(dpToPx(12), dpToPx(6), dpToPx(12), dpToPx(6))
        imageActionContent.visibility = View.GONE

        // Hint text
        val hintTv = TextView(this)
        hintTv.text = "Drag to move · Corners to resize · Pinch to scale"
        hintTv.textSize = 10f
        hintTv.setTextColor(Color.parseColor("#9E9E9E"))
        hintTv.gravity = Gravity.CENTER
        imageActionContent.addView(hintTv, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dpToPx(6) })

        // Button row
        val btnRow = LinearLayout(this)
        btnRow.orientation = LinearLayout.HORIZONTAL
        btnRow.gravity = Gravity.CENTER_VERTICAL

        // Aspect Ratio lock toggle
        val aspectBtn = Button(this)
        aspectBtn.textSize = 12f
        aspectBtn.isAllCaps = false
        aspectBtn.setPadding(dpToPx(12), dpToPx(4), dpToPx(12), dpToPx(4))
        fun updateAspectBtn(locked: Boolean) {
            aspectBtn.text = if (locked) "Aspect: Locked" else "Aspect: Free"
            val bg = GradientDrawable()
            bg.cornerRadius = dpToPx(8).toFloat()
            if (locked) {
                bg.setColor(Color.parseColor("#E3F2FD"))
                bg.setStroke(dpToPx(1), Color.parseColor("#2196F3"))
                aspectBtn.setTextColor(Color.parseColor("#2196F3"))
            } else {
                bg.setColor(Color.parseColor("#FFF3E0"))
                bg.setStroke(dpToPx(1), Color.parseColor("#FF9800"))
                aspectBtn.setTextColor(Color.parseColor("#FF9800"))
            }
            aspectBtn.background = bg
        }
        updateAspectBtn(false)
        aspectBtn.setOnClickListener {
            val newLocked = !(activeImageView?.aspectRatioLocked ?: false)
            drawingViews.forEach { it.aspectRatioLocked = newLocked }
            updateAspectBtn(newLocked)
        }
        btnRow.addView(aspectBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f).apply { marginEnd = dpToPx(8) })

        // Confirm (apply) button
        val applyBtn = Button(this)
        applyBtn.text = "Confirm"
        applyBtn.textSize = 13f
        applyBtn.setTextColor(Color.WHITE)
        applyBtn.isAllCaps = false
        val applyBg = GradientDrawable()
        applyBg.cornerRadius = dpToPx(8).toFloat()
        applyBg.setColor(Color.parseColor("#4CAF50"))
        applyBtn.background = applyBg
        applyBtn.setPadding(dpToPx(14), dpToPx(4), dpToPx(14), dpToPx(4))
        applyBtn.setOnClickListener {
            activeImageView?.acceptSelectedImage()
            // Exit image mode and release scroll lock
            annotationMode = AnnotationMode.NONE
            scrollView.scrollingEnabled = true
            drawingViews.forEach { dv ->
                dv.isEnabled = false
                dv.pendingImageBitmap = null
                dv.isImagePlacementMode = false
            }
            imageBtn?.let { updateToolButtonState(it, false, Color.parseColor("#4CAF50")) }
            hideImageActions()
        }
        btnRow.addView(applyBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f).apply { marginEnd = dpToPx(8) })

        // Delete button
        val deleteBtn = Button(this)
        deleteBtn.text = "Delete"
        deleteBtn.textSize = 13f
        deleteBtn.setTextColor(Color.WHITE)
        deleteBtn.isAllCaps = false
        val deleteBg = GradientDrawable()
        deleteBg.cornerRadius = dpToPx(8).toFloat()
        deleteBg.setColor(Color.parseColor("#F44336"))
        deleteBtn.background = deleteBg
        deleteBtn.setPadding(dpToPx(14), dpToPx(4), dpToPx(14), dpToPx(4))
        deleteBtn.setOnClickListener {
            activeImageView?.deleteSelectedImage()
            // Exit image mode and release scroll lock
            annotationMode = AnnotationMode.NONE
            scrollView.scrollingEnabled = true
            drawingViews.forEach { dv ->
                dv.isEnabled = false
                dv.pendingImageBitmap = null
                dv.isImagePlacementMode = false
            }
            imageBtn?.let { updateToolButtonState(it, false, Color.parseColor("#4CAF50")) }
            hideImageActions()
        }
        btnRow.addView(deleteBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f))

        imageActionContent.addView(btnRow, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        container.addView(imageActionContent, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        return container
    }

    private fun makeToolButton(label: String, iconRes: Int, onClick: () -> Unit): LinearLayout {
        val container = LinearLayout(this)
        container.orientation = LinearLayout.VERTICAL
        container.gravity = Gravity.CENTER
        container.setPadding(dpToPx(2), dpToPx(4), dpToPx(2), dpToPx(2))
        container.setOnClickListener { onClick() }

        val icon = ImageView(this)
        icon.setImageResource(iconRes)
        icon.setColorFilter(Color.parseColor("#9E9E9E"))
        val iconLp = LinearLayout.LayoutParams(dpToPx(22), dpToPx(22))
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
            setPadding(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(24))
        }

        val titleTv = TextView(this).apply {
            text = "Select Image to Insert"
            textSize = 16f
            setTextColor(Color.parseColor("#212121"))
            gravity = Gravity.CENTER
            setTypeface(null, Typeface.BOLD)
        }
        root.addView(titleTv, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dpToPx(16) })

        val scroll = HorizontalScrollView(this)
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        var selectedBitmap: Bitmap? = null

        val thumbSize = dpToPx(90)
        availableImages.forEachIndexed { idx, bmp ->
            val iv = ImageView(this).apply {
                setImageBitmap(bmp)
                scaleType = ImageView.ScaleType.CENTER_CROP
                val bg = GradientDrawable().apply {
                    cornerRadius = dpToPx(12).toFloat()
                    setColor(Color.parseColor("#F5F5F5"))
                    setStroke(dpToPx(2), Color.parseColor("#E0E0E0"))
                }
                background = bg
                clipToOutline = true
                setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))
                setOnClickListener { selectedBitmap = availableImages[idx]; dialog.dismiss() }
            }
            row.addView(iv, LinearLayout.LayoutParams(thumbSize, thumbSize).apply { marginEnd = dpToPx(12) })
        }
        scroll.addView(row)
        root.addView(scroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dpToPx(16) })

        val cancelTv = TextView(this).apply {
            text = "Cancel"
            textSize = 14f
            setTextColor(Color.parseColor("#2196F3"))
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(8), 0, dpToPx(8))
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
                onImagePlaced = { clearPendingImageOnAllViews() }
            }

            drawingViews.add(drawingView)
            frameLayout.addView(imageView)
            frameLayout.addView(drawingView)

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
            document.close()
            out.toByteArray()
        } catch (e: Exception) { null }
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
            text = "Saving..."
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
                Toast.makeText(this@PDFViewerActivity, "Error building PDF", Toast.LENGTH_LONG).show()
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
                Toast.makeText(this@PDFViewerActivity, "PDF saved!", Toast.LENGTH_SHORT).show()
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
