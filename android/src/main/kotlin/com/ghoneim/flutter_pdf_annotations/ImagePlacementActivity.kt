package com.ghoneim.flutter_pdf_annotations

import android.app.Activity
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.*
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import java.io.File

/** Data holder for passing bitmaps & results between activities. */
object ImagePlacementData {
    var availableImages: List<Bitmap> = emptyList()
    var results: MutableList<ImagePlacement> = mutableListOf()

    fun clear() {
        results.clear()
        // Don't clear availableImages — they're owned by PDFViewerActivity
    }
}

data class ImagePlacement(
    val pageIndex: Int,
    val imageIndex: Int,
    val rect: RectF  // in PDF page coordinates
)

class ImagePlacementActivity : AppCompatActivity() {

    companion object {
        private const val MAX_RENDER_DENSITY = 3f
    }

    private var pdfRenderer: PdfRenderer? = null
    private var pageCount = 0
    private var currentPageIndex = 0
    private var currentPageBitmap: Bitmap? = null

    // PDF page dimensions (in PDF points)
    private var pdfPageWidth = 0f
    private var pdfPageHeight = 0f

    // Render transform: view pixels per PDF point
    private var renderScale = 1f
    private var renderOffsetX = 0f
    private var renderOffsetY = 0f

    // Current image being placed
    private var currentImage: Bitmap? = null
    private var currentImageIndex = -1
    private var currentImageRect = RectF()  // in PDF coords
    private var aspectRatioLocked = false

    // Drag state
    private enum class DragMode { NONE, MOVE, TL, TR, BL, BR }
    private var dragMode = DragMode.NONE
    private var dragStartX = 0f
    private var dragStartY = 0f
    private var dragOrigRect = RectF()

    // Pinch state
    private var pinchBaseWidth = 0f
    private var pinchBaseHeight = 0f
    private var pinchBaseCenterX = 0f
    private var pinchBaseCenterY = 0f

    private val minImageSize = 40f
    private val handleRadius = 12f
    private val handleHitRadius = 35f

    // Views
    private lateinit var pageImageView: ImageView
    private lateinit var overlayView: ImageOverlayView
    private lateinit var pageLabel: TextView
    private lateinit var actionRow: LinearLayout
    private lateinit var aspectBtn: Button

    // Already confirmed placements for this session
    private val placements = mutableListOf<ImagePlacement>()

    private lateinit var scaleDetector: ScaleGestureDetector

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val filePath = intent.getStringExtra("filePath") ?: run { finish(); return }
        currentPageIndex = intent.getIntExtra("initialPage", 0)

        try {
            val file = File(filePath)
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            pdfRenderer = PdfRenderer(descriptor)
            pageCount = pdfRenderer!!.pageCount
            currentPageIndex = currentPageIndex.coerceIn(0, pageCount - 1)
        } catch (e: Exception) {
            finish(); return
        }

        scaleDetector = ScaleGestureDetector(this, PinchListener())

        buildUI()
        renderCurrentPage()
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()

    // MARK: - UI Construction

    private fun buildUI() {
        val mainLayout = FrameLayout(this)
        mainLayout.setBackgroundColor(Color.parseColor("#F5F5F5"))

        // Page image view
        pageImageView = ImageView(this)
        pageImageView.scaleType = ImageView.ScaleType.FIT_CENTER
        pageImageView.setBackgroundColor(Color.WHITE)

        // Overlay for image drag/resize
        overlayView = ImageOverlayView(this)

        val topBar = buildTopBar()
        val bottomBar = buildBottomBar()

        val topBarHeight = dpToPx(52)
        val bottomBarHeight = dpToPx(180)

        // Content area
        val contentFrame = FrameLayout(this)
        contentFrame.addView(pageImageView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        contentFrame.addView(overlayView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val contentLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        contentLp.topMargin = topBarHeight
        contentLp.bottomMargin = bottomBarHeight
        mainLayout.addView(contentFrame, contentLp)

        val topLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        topLp.gravity = Gravity.TOP
        mainLayout.addView(topBar, topLp)

        val bottomLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        bottomLp.gravity = Gravity.BOTTOM
        mainLayout.addView(bottomBar, bottomLp)

        setContentView(mainLayout)
    }

    private fun buildTopBar(): LinearLayout {
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setBackgroundColor(Color.WHITE)
        bar.elevation = dpToPx(2).toFloat()
        bar.setPadding(dpToPx(8), dpToPx(8), dpToPx(8), dpToPx(8))

        val backBtn = Button(this).apply {
            text = "Back"; setTextColor(Color.parseColor("#2196F3"))
            background = null; isAllCaps = false
            setOnClickListener { handleBack() }
        }
        bar.addView(backBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val prevBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_media_previous)
            background = null; setColorFilter(Color.parseColor("#2196F3"))
            setOnClickListener { prevPage() }
        }
        bar.addView(prevBtn, LinearLayout.LayoutParams(dpToPx(40), dpToPx(40)))

        pageLabel = TextView(this).apply {
            textSize = 15f; gravity = Gravity.CENTER
            setTextColor(Color.parseColor("#212121"))
            setTypeface(null, Typeface.BOLD)
        }
        bar.addView(pageLabel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val nextBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_media_next)
            background = null; setColorFilter(Color.parseColor("#2196F3"))
            setOnClickListener { nextPage() }
        }
        bar.addView(nextBtn, LinearLayout.LayoutParams(dpToPx(40), dpToPx(40)))

        val doneBtn = Button(this).apply {
            text = "Done"; isAllCaps = false
            setTextColor(Color.WHITE)
            setTypeface(null, Typeface.BOLD)
            val bg = GradientDrawable()
            bg.cornerRadius = dpToPx(8).toFloat()
            bg.setColor(Color.parseColor("#2196F3"))
            background = bg
            setPadding(dpToPx(16), dpToPx(4), dpToPx(16), dpToPx(4))
            setOnClickListener { handleDone() }
        }
        bar.addView(doneBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dpToPx(36)))

        return bar
    }

    private fun buildBottomBar(): LinearLayout {
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.VERTICAL
        bar.setBackgroundColor(Color.WHITE)
        bar.elevation = dpToPx(4).toFloat()
        bar.setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(16))

        // Separator
        val sep = View(this)
        sep.setBackgroundColor(Color.parseColor("#E0E0E0"))
        bar.addView(sep, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpToPx(1)).apply {
            bottomMargin = dpToPx(8)
        })

        // Image thumbnails in horizontal scroll
        val scroll = HorizontalScrollView(this)
        scroll.isHorizontalScrollBarEnabled = false
        val thumbRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        val thumbSize = dpToPx(64)
        ImagePlacementData.availableImages.forEachIndexed { idx, bmp ->
            val iv = ImageView(this).apply {
                setImageBitmap(bmp)
                scaleType = ImageView.ScaleType.CENTER_CROP
                val bg = GradientDrawable().apply {
                    cornerRadius = dpToPx(8).toFloat()
                    setColor(Color.parseColor("#F5F5F5"))
                    setStroke(dpToPx(2), Color.parseColor("#E0E0E0"))
                }
                background = bg
                clipToOutline = true
                setPadding(dpToPx(2), dpToPx(2), dpToPx(2), dpToPx(2))
                setOnClickListener { placeImage(idx) }
            }
            thumbRow.addView(iv, LinearLayout.LayoutParams(thumbSize, thumbSize).apply {
                marginEnd = dpToPx(12)
            })
        }
        scroll.addView(thumbRow)
        bar.addView(scroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dpToPx(8)
        })

        // Action row (hidden when no image placed)
        actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
        }

        aspectBtn = Button(this).apply {
            textSize = 12f; isAllCaps = false
            setPadding(dpToPx(12), dpToPx(4), dpToPx(12), dpToPx(4))
            setOnClickListener { toggleAspectRatio() }
        }
        updateAspectBtnUI()
        actionRow.addView(aspectBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f).apply {
            marginEnd = dpToPx(8)
        })

        val confirmBtn = Button(this).apply {
            text = "Confirm"; textSize = 13f; isAllCaps = false
            setTextColor(Color.WHITE)
            val bg = GradientDrawable(); bg.cornerRadius = dpToPx(8).toFloat()
            bg.setColor(Color.parseColor("#4CAF50")); background = bg
            setPadding(dpToPx(14), dpToPx(4), dpToPx(14), dpToPx(4))
            setOnClickListener { confirmCurrentImage() }
        }
        actionRow.addView(confirmBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f).apply {
            marginEnd = dpToPx(8)
        })

        val deleteBtn = Button(this).apply {
            text = "Delete"; textSize = 13f; isAllCaps = false
            setTextColor(Color.WHITE)
            val bg = GradientDrawable(); bg.cornerRadius = dpToPx(8).toFloat()
            bg.setColor(Color.parseColor("#F44336")); background = bg
            setPadding(dpToPx(14), dpToPx(4), dpToPx(14), dpToPx(4))
            setOnClickListener { deleteCurrentImage() }
        }
        actionRow.addView(deleteBtn, LinearLayout.LayoutParams(0, dpToPx(36), 1f))

        bar.addView(actionRow, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        return bar
    }

    // MARK: - Page Rendering

    private fun renderCurrentPage() {
        val renderer = pdfRenderer ?: return
        currentPageBitmap?.recycle()

        renderer.openPage(currentPageIndex).use { page ->
            pdfPageWidth = page.width.toFloat()
            pdfPageHeight = page.height.toFloat()

            val density = resources.displayMetrics.density.coerceAtMost(MAX_RENDER_DENSITY)
            val renderWidth = (page.width * density).toInt()
            val renderHeight = (page.height * density).toInt()

            val bitmap = Bitmap.createBitmap(renderWidth, renderHeight, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            // Draw already-confirmed placements on this page
            val canvas = Canvas(bitmap)
            val scaleX = renderWidth.toFloat() / pdfPageWidth
            val scaleY = renderHeight.toFloat() / pdfPageHeight
            for (p in placements) {
                if (p.pageIndex != currentPageIndex) continue
                val img = ImagePlacementData.availableImages.getOrNull(p.imageIndex) ?: continue
                val drawRect = RectF(
                    p.rect.left * scaleX, p.rect.top * scaleY,
                    p.rect.right * scaleX, p.rect.bottom * scaleY
                )
                canvas.drawBitmap(img, null, drawRect, Paint().apply { isFilterBitmap = true })
            }

            currentPageBitmap = bitmap
            pageImageView.setImageBitmap(bitmap)
        }

        pageLabel.text = "Page ${currentPageIndex + 1}/$pageCount"

        // Update render transform after layout
        pageImageView.post { updateRenderTransform() }
    }

    private fun updateRenderTransform() {
        val bitmap = currentPageBitmap ?: return
        val ivW = pageImageView.width.toFloat()
        val ivH = pageImageView.height.toFloat()
        if (ivW <= 0 || ivH <= 0) return

        val bmpW = bitmap.width.toFloat()
        val bmpH = bitmap.height.toFloat()
        val scaleW = ivW / bmpW
        val scaleH = ivH / bmpH
        val fitScale = minOf(scaleW, scaleH)

        val displayW = bmpW * fitScale
        val displayH = bmpH * fitScale
        renderOffsetX = (ivW - displayW) / 2f
        renderOffsetY = (ivH - displayH) / 2f

        // renderScale: view pixels per PDF point
        renderScale = displayW / pdfPageWidth
        overlayView.invalidate()
    }

    // MARK: - Coordinate Conversion

    private fun pdfToViewX(pdfX: Float): Float = renderOffsetX + pdfX * renderScale
    private fun pdfToViewY(pdfY: Float): Float = renderOffsetY + pdfY * renderScale
    private fun viewToPdfX(viewX: Float): Float = (viewX - renderOffsetX) / renderScale
    private fun viewToPdfY(viewY: Float): Float = (viewY - renderOffsetY) / renderScale

    private fun pdfRectToView(r: RectF): RectF = RectF(
        pdfToViewX(r.left), pdfToViewY(r.top),
        pdfToViewX(r.right), pdfToViewY(r.bottom)
    )

    // MARK: - Image Placement

    private fun placeImage(imageIndex: Int) {
        val bmp = ImagePlacementData.availableImages.getOrNull(imageIndex) ?: return
        currentImage = bmp
        currentImageIndex = imageIndex

        // Center on page, 35% width
        val imgW = pdfPageWidth * 0.35f
        val imgH = imgW * bmp.height / bmp.width
        currentImageRect = RectF(
            pdfPageWidth / 2 - imgW / 2, pdfPageHeight / 2 - imgH / 2,
            pdfPageWidth / 2 + imgW / 2, pdfPageHeight / 2 + imgH / 2
        )

        actionRow.visibility = View.VISIBLE
        overlayView.invalidate()
    }

    private fun confirmCurrentImage() {
        if (currentImage == null) return
        placements.add(ImagePlacement(currentPageIndex, currentImageIndex, RectF(currentImageRect)))
        currentImage = null
        currentImageIndex = -1
        actionRow.visibility = View.GONE
        renderCurrentPage()  // re-render with confirmed image baked in
    }

    private fun deleteCurrentImage() {
        currentImage = null
        currentImageIndex = -1
        actionRow.visibility = View.GONE
        overlayView.invalidate()
    }

    private fun toggleAspectRatio() {
        aspectRatioLocked = !aspectRatioLocked
        updateAspectBtnUI()
    }

    private fun updateAspectBtnUI() {
        val bg = GradientDrawable()
        bg.cornerRadius = dpToPx(8).toFloat()
        if (aspectRatioLocked) {
            aspectBtn.text = "Aspect: Locked"
            bg.setColor(Color.parseColor("#E3F2FD"))
            bg.setStroke(dpToPx(1), Color.parseColor("#2196F3"))
            aspectBtn.setTextColor(Color.parseColor("#2196F3"))
        } else {
            aspectBtn.text = "Aspect: Free"
            bg.setColor(Color.parseColor("#FFF3E0"))
            bg.setStroke(dpToPx(1), Color.parseColor("#FF9800"))
            aspectBtn.setTextColor(Color.parseColor("#FF9800"))
        }
        aspectBtn.background = bg
    }

    // MARK: - Navigation

    private fun prevPage() {
        if (currentPageIndex <= 0) return
        if (currentImage != null) confirmCurrentImage()
        currentPageIndex--
        currentImage = null; actionRow.visibility = View.GONE
        renderCurrentPage()
    }

    private fun nextPage() {
        if (currentPageIndex >= pageCount - 1) return
        if (currentImage != null) confirmCurrentImage()
        currentPageIndex++
        currentImage = null; actionRow.visibility = View.GONE
        renderCurrentPage()
    }

    private fun handleBack() {
        if (currentImage != null) {
            AlertDialog.Builder(this)
                .setTitle("Discard Image?")
                .setMessage("You have an unconfirmed image placement.")
                .setPositiveButton("Discard") { _, _ ->
                    currentImage = null
                    returnResults()
                }
                .setNegativeButton("Cancel", null)
                .show()
        } else {
            returnResults()
        }
    }

    private fun handleDone() {
        if (currentImage != null) confirmCurrentImage()
        returnResults()
    }

    private fun returnResults() {
        ImagePlacementData.results = placements.toMutableList()
        setResult(Activity.RESULT_OK)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        pdfRenderer?.close()
        currentPageBitmap?.let { if (!it.isRecycled) it.recycle() }
    }

    // MARK: - Touch Handling on Overlay

    fun handleOverlayTouch(event: MotionEvent): Boolean {
        if (currentImage == null) return false

        // Pinch detection
        if (event.pointerCount >= 2) {
            scaleDetector.onTouchEvent(event)
            return true
        }

        val viewX = event.x
        val viewY = event.y
        val pdfX = viewToPdfX(viewX)
        val pdfY = viewToPdfY(viewY)

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val viewRect = pdfRectToView(currentImageRect)
                // Corner handles
                val corners = listOf(
                    PointF(viewRect.left, viewRect.top) to DragMode.TL,
                    PointF(viewRect.right, viewRect.top) to DragMode.TR,
                    PointF(viewRect.left, viewRect.bottom) to DragMode.BL,
                    PointF(viewRect.right, viewRect.bottom) to DragMode.BR,
                )
                for ((pt, mode) in corners) {
                    if (dist(viewX, viewY, pt.x, pt.y) <= handleHitRadius) {
                        dragMode = mode
                        dragStartX = pdfX; dragStartY = pdfY
                        dragOrigRect = RectF(currentImageRect)
                        return true
                    }
                }
                // Body drag
                if (viewRect.contains(viewX, viewY)) {
                    dragMode = DragMode.MOVE
                    dragStartX = pdfX; dragStartY = pdfY
                    dragOrigRect = RectF(currentImageRect)
                    return true
                }
                return false
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragMode == DragMode.NONE) return false
                val dx = pdfX - dragStartX
                val dy = pdfY - dragStartY
                val orig = dragOrigRect

                when (dragMode) {
                    DragMode.MOVE -> currentImageRect.set(
                        orig.left + dx, orig.top + dy,
                        orig.right + dx, orig.bottom + dy)
                    DragMode.TL, DragMode.TR, DragMode.BL, DragMode.BR -> {
                        if (aspectRatioLocked) {
                            resizeAspectLocked(orig, dx, dy)
                        } else {
                            resizeFree(orig, dx, dy)
                        }
                    }
                    DragMode.NONE -> {}
                }
                overlayView.invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragMode != DragMode.NONE) {
                    dragMode = DragMode.NONE
                    return true
                }
                return false
            }
        }
        return false
    }

    private fun dist(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x1 - x2; val dy = y1 - y2
        return Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
    }

    // MARK: - Resize Helpers

    private fun resizeFree(orig: RectF, dx: Float, dy: Float) {
        val min = minImageSize
        when (dragMode) {
            DragMode.TL -> currentImageRect.set(
                minOf(orig.left + dx, orig.right - min), minOf(orig.top + dy, orig.bottom - min),
                orig.right, orig.bottom)
            DragMode.TR -> currentImageRect.set(
                orig.left, minOf(orig.top + dy, orig.bottom - min),
                maxOf(orig.right + dx, orig.left + min), orig.bottom)
            DragMode.BL -> currentImageRect.set(
                minOf(orig.left + dx, orig.right - min), orig.top,
                orig.right, maxOf(orig.bottom + dy, orig.top + min))
            DragMode.BR -> currentImageRect.set(
                orig.left, orig.top,
                maxOf(orig.right + dx, orig.left + min), maxOf(orig.bottom + dy, orig.top + min))
            else -> {}
        }
    }

    private fun resizeAspectLocked(orig: RectF, dx: Float, dy: Float) {
        val origW = orig.width(); val origH = orig.height()
        if (origW < 1f || origH < 1f) return
        val aspect = origW / origH
        val anchorRight = (dragMode == DragMode.TL || dragMode == DragMode.BL)
        val anchorBottom = (dragMode == DragMode.TL || dragMode == DragMode.TR)
        val signX = if (anchorRight) -1f else 1f
        val signY = if (anchorBottom) -1f else 1f
        val proj = (signX * dx + signY * dy) / 2f
        var newW = (origW + proj * 2f * (if (signX < 0) -1f else 1f)).coerceAtLeast(minImageSize)
        var newH = newW / aspect
        if (newH < minImageSize) { newH = minImageSize; newW = newH * aspect }
        val aX = if (anchorRight) orig.right else orig.left
        val aY = if (anchorBottom) orig.bottom else orig.top
        val l = if (anchorRight) aX - newW else aX
        val t = if (anchorBottom) aY - newH else aY
        currentImageRect.set(l, t, l + newW, t + newH)
    }

    // MARK: - Pinch Listener

    private inner class PinchListener : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
            if (currentImage == null) return false
            pinchBaseWidth = currentImageRect.width()
            pinchBaseHeight = currentImageRect.height()
            pinchBaseCenterX = currentImageRect.centerX()
            pinchBaseCenterY = currentImageRect.centerY()
            return true
        }

        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val scale = detector.scaleFactor.coerceIn(0.3f, 5.0f)
            var newW = (pinchBaseWidth * scale).coerceAtLeast(minImageSize)
            var newH = if (aspectRatioLocked) {
                newW * pinchBaseHeight / pinchBaseWidth
            } else {
                (pinchBaseHeight * scale).coerceAtLeast(minImageSize)
            }
            if (newH < minImageSize) { newH = minImageSize; newW = newH * pinchBaseWidth / pinchBaseHeight }
            currentImageRect.set(
                pinchBaseCenterX - newW / 2, pinchBaseCenterY - newH / 2,
                pinchBaseCenterX + newW / 2, pinchBaseCenterY + newH / 2
            )
            overlayView.invalidate()
            return true
        }
    }

    // MARK: - Overlay View

    inner class ImageOverlayView(context: android.content.Context) : View(context) {
        override fun onTouchEvent(event: MotionEvent): Boolean {
            return handleOverlayTouch(event) || super.onTouchEvent(event)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val img = currentImage ?: return
            val viewRect = pdfRectToView(currentImageRect)

            // Draw the image
            canvas.drawBitmap(img, null, viewRect, Paint().apply { isFilterBitmap = true })

            // Selection overlay
            canvas.drawRect(viewRect, Paint().apply {
                style = Paint.Style.FILL; color = Color.argb(15, 33, 150, 243)
            })

            // Dashed border
            canvas.drawRect(viewRect, Paint().apply {
                style = Paint.Style.STROKE; color = Color.parseColor("#2196F3")
                strokeWidth = 2.5f
                pathEffect = DashPathEffect(floatArrayOf(8f, 4f), 0f)
                isAntiAlias = true
            })

            // Corner handles
            val r = handleRadius
            val corners = listOf(
                PointF(viewRect.left, viewRect.top),
                PointF(viewRect.right, viewRect.top),
                PointF(viewRect.left, viewRect.bottom),
                PointF(viewRect.right, viewRect.bottom),
            )
            val fillP = Paint().apply { style = Paint.Style.FILL; color = Color.WHITE; isAntiAlias = true }
            val shadowP = Paint().apply { style = Paint.Style.FILL; color = Color.argb(40, 0, 0, 0); isAntiAlias = true }
            val strokeP = Paint().apply {
                style = Paint.Style.STROKE; color = Color.parseColor("#2196F3")
                strokeWidth = 2.5f; isAntiAlias = true
            }
            for (pt in corners) {
                canvas.drawCircle(pt.x, pt.y + 1f, r * 1.1f, shadowP)
                canvas.drawCircle(pt.x, pt.y, r, fillP)
                canvas.drawCircle(pt.x, pt.y, r, strokeP)
            }
        }
    }
}
