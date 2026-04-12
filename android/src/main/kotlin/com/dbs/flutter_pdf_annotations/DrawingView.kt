package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View

class DrawingView(context: Context) : View(context) {
    private var paint = Paint().apply {
        isAntiAlias = true
        strokeWidth = 5f
        color = Color.RED
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    private var currentPath: Path? = null
    private var paths = mutableListOf<AnnotationData>()
    private var matrix = Matrix()
    private var inverseMatrix = Matrix()
    private var originalStrokeWidth = 5f
    private var isEraserMode = false

    private val highlights = mutableListOf<HighlightAnnotationData>()
    private var currentHighlightRect: RectF? = null
    private var highlightStartX = 0f
    private var highlightStartY = 0f
    private var isHighlightMode = false
    private var highlightColor = Color.argb(128, 255, 255, 0)
    private val annotationHistory = mutableListOf<AnnotationType>()

    // Image annotation state
    private val imageAnnotations = mutableListOf<ImageAnnotationData>()
    private var selectedImageIndex = -1
    private var dragMode = DragMode.NONE
    private var dragStart = PointF()
    private var dragOrigRect: RectF? = null

    var pendingImageBitmap: Bitmap? = null
    var isImagePlacementMode = false
    var pageBitmapWidth = 0f
    var pageBitmapHeight = 0f
    var onImagePlaced: (() -> Unit)? = null
    var onStrokeAdded: (() -> Unit)? = null

    /** Called whenever an image is selected (true) or deselected (false). */
    var onImageSelectionChanged: ((Boolean) -> Unit)? = null

    /** Aspect ratio lock — default is FREE */
    var aspectRatioLocked = false

    /** Last confirmed image rect in PDF coords — used to place the next image at the same spot */
    var lastConfirmedImageRect: RectF? = null

    // Pinch-to-resize for selected image
    private var pinchBaseWidth = 0f
    private var pinchBaseHeight = 0f
    private var pinchBaseCenterX = 0f
    private var pinchBaseCenterY = 0f

    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
            if (selectedImageIndex < 0) return false
            val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return false
            pinchBaseWidth = img.rect.width()
            pinchBaseHeight = img.rect.height()
            pinchBaseCenterX = img.rect.centerX()
            pinchBaseCenterY = img.rect.centerY()
            return true
        }

        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return false
            val scale = detector.scaleFactor.coerceIn(0.3f, 5.0f)
            val newW = (pinchBaseWidth * scale).coerceAtLeast(MIN_IMAGE_SIZE)
            val newH = if (aspectRatioLocked) {
                newW * pinchBaseHeight / pinchBaseWidth
            } else {
                (pinchBaseHeight * scale).coerceAtLeast(MIN_IMAGE_SIZE)
            }
            img.rect.set(
                pinchBaseCenterX - newW / 2, pinchBaseCenterY - newH / 2,
                pinchBaseCenterX + newW / 2, pinchBaseCenterY + newH / 2
            )
            invalidate()
            return true
        }
    })

    data class AnnotationData(val path: Path, val strokeWidth: Float, val color: Int)
    data class HighlightAnnotationData(val rect: RectF, val color: Int)
    data class ImageAnnotationData(val bitmap: Bitmap, var rect: RectF)

    enum class AnnotationType { PATH, HIGHLIGHT, IMAGE }
    private enum class DragMode { NONE, MOVE, TL, TR, BL, BR }

    companion object {
        private const val MIN_IMAGE_SIZE = 40f
        private const val HANDLE_VISUAL_RADIUS = 12f
        private const val ACTION_BUTTON_RADIUS = 16f
    }

    fun setColor(color: Int) { paint = Paint(paint).apply { this.color = color } }
    fun setStrokeWidth(width: Float) { originalStrokeWidth = width; updatePaintStrokeWidth() }
    fun setEraserMode(enabled: Boolean) { isEraserMode = enabled }
    fun setHighlightMode(enabled: Boolean) { isHighlightMode = enabled }
    fun setHighlightColor(color: Int) { highlightColor = color }

    fun setTransformMatrix(m: Matrix) {
        matrix = Matrix(m)
        matrix.invert(inverseMatrix)
        updatePaintStrokeWidth()
        invalidate()
    }

    private fun updatePaintStrokeWidth() {
        val scale = matrixScaleX()
        paint.strokeWidth = if (scale > 0) originalStrokeWidth / scale else originalStrokeWidth
    }

    private fun matrixScaleX(): Float {
        val values = FloatArray(9)
        matrix.getValues(values)
        return values[Matrix.MSCALE_X].takeIf { it > 0 } ?: 1f
    }

    private fun handleRadiusPdf(): Float = HANDLE_VISUAL_RADIUS / matrixScaleX()
    private fun actionBtnRadiusPdf(): Float = ACTION_BUTTON_RADIUS / matrixScaleX()

    fun getAnnotations(): List<AnnotationData> = paths.toList()
    fun getHighlights(): List<HighlightAnnotationData> = highlights.toList()
    fun getImageAnnotations(): List<ImageAnnotationData> = imageAnnotations.toList()
    fun hasSelectedImage(): Boolean = selectedImageIndex >= 0

    fun placeImage(bitmap: Bitmap, cx: Float, cy: Float) {
        // If we have a last confirmed rect, place at that location/size instead
        val rect = lastConfirmedImageRect?.let { prev ->
            val w = prev.width()
            val h = prev.height()
            RectF(prev.centerX() - w / 2, prev.centerY() - h / 2,
                  prev.centerX() + w / 2, prev.centerY() + h / 2)
        } ?: run {
            val refWidth = if (pageBitmapWidth > 0) pageBitmapWidth else width.toFloat()
            val imgW = refWidth * 0.35f
            val imgH = imgW * bitmap.height.toFloat() / bitmap.width.toFloat()
            RectF(cx - imgW / 2, cy - imgH / 2, cx + imgW / 2, cy + imgH / 2)
        }
        imageAnnotations.add(ImageAnnotationData(bitmap, rect))
        selectedImageIndex = imageAnnotations.size - 1
        annotationHistory.add(AnnotationType.IMAGE)
        pendingImageBitmap = null
        isImagePlacementMode = false
        onImagePlaced?.invoke()
        onStrokeAdded?.invoke()
        onImageSelectionChanged?.invoke(true)
        invalidate()
    }

    /** Confirm: burn the image (keep it), save position, deselect. */
    fun acceptSelectedImage() {
        if (selectedImageIndex >= 0 && selectedImageIndex < imageAnnotations.size) {
            lastConfirmedImageRect = RectF(imageAnnotations[selectedImageIndex].rect)
        }
        selectedImageIndex = -1
        dragMode = DragMode.NONE
        onImageSelectionChanged?.invoke(false)
        invalidate()
    }

    /** Delete the selected image. */
    fun deleteSelectedImage() {
        if (selectedImageIndex < 0 || selectedImageIndex >= imageAnnotations.size) return
        imageAnnotations.removeAt(selectedImageIndex)
        val histIdx = annotationHistory.lastIndexOf(AnnotationType.IMAGE)
        if (histIdx >= 0) annotationHistory.removeAt(histIdx)
        selectedImageIndex = -1
        dragMode = DragMode.NONE
        onImageSelectionChanged?.invoke(false)
        invalidate()
    }

    fun deselectAll() {
        if (selectedImageIndex >= 0) {
            selectedImageIndex = -1
            onImageSelectionChanged?.invoke(false)
        }
        invalidate()
    }

    private fun confirmButtonCenter(): PointF? {
        val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return null
        val btnR = actionBtnRadiusPdf()
        return PointF(img.rect.centerX(), img.rect.bottom + btnR + 6f / matrixScaleX())
    }

    private fun deleteButtonCenter(): PointF? {
        val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return null
        return PointF(img.rect.centerX(), img.rect.top)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.concat(matrix)

        val highlightPaint = Paint().apply { style = Paint.Style.FILL }
        highlights.forEach { h -> highlightPaint.color = h.color; canvas.drawRect(h.rect, highlightPaint) }
        currentHighlightRect?.let { canvas.drawRect(it, Paint().apply { style = Paint.Style.FILL; color = highlightColor }) }

        val r = handleRadiusPdf()
        val scale = matrixScaleX()
        val btnR = actionBtnRadiusPdf()
        imageAnnotations.forEachIndexed { idx, img ->
            canvas.drawBitmap(img.bitmap, null, img.rect, null)
            if (idx == selectedImageIndex) {
                // Selection overlay
                canvas.drawRect(img.rect, Paint().apply {
                    style = Paint.Style.FILL; color = Color.argb(20, 33, 150, 243)
                })
                // Dashed border
                canvas.drawRect(img.rect, Paint().apply {
                    style = Paint.Style.STROKE; color = Color.parseColor("#2196F3")
                    strokeWidth = 2.5f / scale
                    pathEffect = DashPathEffect(floatArrayOf(8f / scale, 4f / scale), 0f)
                    isAntiAlias = true
                })
                // Corner handles
                val fillP = Paint().apply { style = Paint.Style.FILL; color = Color.WHITE; isAntiAlias = true }
                val shadowP = Paint().apply { style = Paint.Style.FILL; color = Color.argb(40, 0, 0, 0); isAntiAlias = true }
                val strokeP = Paint().apply {
                    style = Paint.Style.STROKE; color = Color.parseColor("#2196F3")
                    strokeWidth = 2.5f / scale; isAntiAlias = true
                }
                for (pt in cornerPoints(img.rect)) {
                    canvas.drawCircle(pt.x, pt.y + 1f / scale, r * 1.1f, shadowP)
                    canvas.drawCircle(pt.x, pt.y, r, fillP)
                    canvas.drawCircle(pt.x, pt.y, r, strokeP)
                }

                // Delete button (top-center)
                val del = deleteButtonCenter()!!
                canvas.drawCircle(del.x, del.y + 1f / scale, btnR * 1.05f, shadowP)
                canvas.drawCircle(del.x, del.y, btnR, Paint().apply {
                    style = Paint.Style.FILL; color = Color.parseColor("#F44336"); isAntiAlias = true
                })
                val xOff = btnR * 0.4f
                val xP = Paint().apply {
                    style = Paint.Style.STROKE; color = Color.WHITE; strokeWidth = 2.5f / scale
                    strokeCap = Paint.Cap.ROUND; isAntiAlias = true
                }
                canvas.drawLine(del.x - xOff, del.y - xOff, del.x + xOff, del.y + xOff, xP)
                canvas.drawLine(del.x + xOff, del.y - xOff, del.x - xOff, del.y + xOff, xP)

                // Confirm button (bottom-center)
                val cfm = confirmButtonCenter()!!
                canvas.drawCircle(cfm.x, cfm.y + 1f / scale, btnR * 1.05f, shadowP)
                canvas.drawCircle(cfm.x, cfm.y, btnR, Paint().apply {
                    style = Paint.Style.FILL; color = Color.parseColor("#4CAF50"); isAntiAlias = true
                })
                val ckP = Paint().apply {
                    style = Paint.Style.STROKE; color = Color.WHITE; strokeWidth = 2.5f / scale
                    strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; isAntiAlias = true
                }
                val ckPath = Path()
                ckPath.moveTo(cfm.x - btnR * 0.35f, cfm.y)
                ckPath.lineTo(cfm.x - btnR * 0.05f, cfm.y + btnR * 0.3f)
                ckPath.lineTo(cfm.x + btnR * 0.4f, cfm.y - btnR * 0.3f)
                canvas.drawPath(ckPath, ckP)
            }
        }

        // Paths
        paths.forEach { a -> paint.color = a.color; paint.strokeWidth = a.strokeWidth; canvas.drawPath(a.path, paint) }
        currentPath?.let { canvas.drawPath(it, paint) }

        // Image placement hint
        if (isImagePlacementMode && pendingImageBitmap != null) {
            val hintPaint = Paint().apply {
                color = Color.argb(140, 33, 150, 243)
                textSize = 16f / scale; textAlign = Paint.Align.CENTER
                isAntiAlias = true; typeface = Typeface.DEFAULT_BOLD
            }
            val cx = (if (pageBitmapWidth > 0) pageBitmapWidth else width.toFloat()) / 2f
            val cy = (if (pageBitmapHeight > 0) pageBitmapHeight else height.toFloat()) / 2f
            canvas.drawText("Tap to place image", cx, cy, hintPaint)
        }

        canvas.restore()
    }

    private fun cornerPoints(rect: RectF) = listOf(
        PointF(rect.left, rect.top), PointF(rect.right, rect.top),
        PointF(rect.left, rect.bottom), PointF(rect.right, rect.bottom)
    )

    private fun dist(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x1 - x2; val dy = y1 - y2
        return Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false

        if (selectedImageIndex >= 0 && event.pointerCount >= 2) {
            scaleDetector.onTouchEvent(event)
            return true
        }

        val pts = floatArrayOf(event.x, event.y)
        inverseMatrix.mapPoints(pts)
        val x = pts[0]; val y = pts[1]

        if (isImagePlacementMode && pendingImageBitmap != null) {
            if (event.action == MotionEvent.ACTION_UP) placeImage(pendingImageBitmap!!, x, y)
            return true
        }

        if (handleImageTouch(event, x, y)) return true

        if (isHighlightMode) {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { highlightStartX = x; highlightStartY = y; return true }
                MotionEvent.ACTION_MOVE -> {
                    currentHighlightRect = RectF(minOf(highlightStartX, x), minOf(highlightStartY, y), maxOf(highlightStartX, x), maxOf(highlightStartY, y))
                    invalidate(); return true
                }
                MotionEvent.ACTION_UP -> {
                    val rect = RectF(minOf(highlightStartX, x), minOf(highlightStartY, y), maxOf(highlightStartX, x), maxOf(highlightStartY, y))
                    if (rect.width() > 5f && rect.height() > 5f) {
                        highlights.add(HighlightAnnotationData(rect, highlightColor))
                        annotationHistory.add(AnnotationType.HIGHLIGHT)
                        onStrokeAdded?.invoke()
                    }
                    currentHighlightRect = null; invalidate(); return true
                }
            }
            return false
        }

        if (isEraserMode) {
            if (event.action == MotionEvent.ACTION_DOWN || event.action == MotionEvent.ACTION_MOVE) {
                val eraserRect = RectF(x - 20f, y - 20f, x + 20f, y + 20f)
                val pathBounds = RectF()
                val removed = paths.removeAll { a -> a.path.computeBounds(pathBounds, true); RectF.intersects(pathBounds, eraserRect) }
                if (removed) invalidate()
            }
            return true
        }

        when (event.action) {
            MotionEvent.ACTION_DOWN -> { currentPath = Path().apply { moveTo(x, y) }; return true }
            MotionEvent.ACTION_MOVE -> { currentPath?.lineTo(x, y); invalidate(); return true }
            MotionEvent.ACTION_UP -> {
                currentPath?.let {
                    paths.add(AnnotationData(it, paint.strokeWidth, paint.color))
                    annotationHistory.add(AnnotationType.PATH)
                    onStrokeAdded?.invoke()
                }
                currentPath = null; invalidate(); return true
            }
            else -> return false
        }
    }

    private fun handleImageTouch(event: MotionEvent, x: Float, y: Float): Boolean {
        val hitR = handleRadiusPdf() * 3.5f
        val btnHitR = actionBtnRadiusPdf() * 2f
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                if (selectedImageIndex >= 0) {
                    val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return false

                    // Confirm button
                    confirmButtonCenter()?.let { cfm ->
                        if (dist(x, y, cfm.x, cfm.y) <= btnHitR) {
                            acceptSelectedImage()
                            return true
                        }
                    }
                    // Delete button
                    deleteButtonCenter()?.let { del ->
                        if (dist(x, y, del.x, del.y) <= btnHitR) {
                            deleteSelectedImage()
                            return true
                        }
                    }
                    // Corners
                    val corners = cornerPoints(img.rect)
                    val modes = listOf(DragMode.TL, DragMode.TR, DragMode.BL, DragMode.BR)
                    for ((i, pt) in corners.withIndex()) {
                        if (dist(x, y, pt.x, pt.y) <= hitR) {
                            dragMode = modes[i]; dragStart.set(x, y); dragOrigRect = RectF(img.rect); return true
                        }
                    }
                    if (img.rect.contains(x, y)) {
                        dragMode = DragMode.MOVE; dragStart.set(x, y); dragOrigRect = RectF(img.rect); return true
                    }
                    selectedImageIndex = -1
                    onImageSelectionChanged?.invoke(false)
                    invalidate(); return true
                }
                for (i in imageAnnotations.indices.reversed()) {
                    if (imageAnnotations[i].rect.contains(x, y)) {
                        selectedImageIndex = i
                        dragMode = DragMode.MOVE; dragStart.set(x, y); dragOrigRect = RectF(imageAnnotations[i].rect)
                        onImageSelectionChanged?.invoke(true)
                        invalidate(); return true
                    }
                }
                return false
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragMode == DragMode.NONE) return false
                val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return false
                val orig = dragOrigRect ?: return false
                val dx = x - dragStart.x; val dy = y - dragStart.y

                when (dragMode) {
                    DragMode.MOVE -> img.rect.set(orig.left + dx, orig.top + dy, orig.right + dx, orig.bottom + dy)
                    DragMode.TL, DragMode.TR, DragMode.BL, DragMode.BR -> {
                        if (aspectRatioLocked) {
                            resizeAspectLocked(img, orig, dx, dy,
                                anchorRight = dragMode == DragMode.TL || dragMode == DragMode.BL,
                                anchorBottom = dragMode == DragMode.TL || dragMode == DragMode.TR)
                        } else {
                            resizeFree(img, orig, dx, dy)
                        }
                    }
                    else -> {}
                }
                invalidate(); return true
            }
            MotionEvent.ACTION_UP -> {
                if (dragMode != DragMode.NONE) { dragMode = DragMode.NONE; dragOrigRect = null; return true }
                return false
            }
            else -> return false
        }
    }

    private fun resizeFree(img: ImageAnnotationData, orig: RectF, dx: Float, dy: Float) {
        val min = MIN_IMAGE_SIZE
        when (dragMode) {
            DragMode.TL -> img.rect.set(minOf(orig.left + dx, orig.right - min), minOf(orig.top + dy, orig.bottom - min), orig.right, orig.bottom)
            DragMode.TR -> img.rect.set(orig.left, minOf(orig.top + dy, orig.bottom - min), maxOf(orig.right + dx, orig.left + min), orig.bottom)
            DragMode.BL -> img.rect.set(minOf(orig.left + dx, orig.right - min), orig.top, orig.right, maxOf(orig.bottom + dy, orig.top + min))
            DragMode.BR -> img.rect.set(orig.left, orig.top, maxOf(orig.right + dx, orig.left + min), maxOf(orig.bottom + dy, orig.top + min))
            else -> {}
        }
    }

    private fun resizeAspectLocked(
        img: ImageAnnotationData, orig: RectF,
        dx: Float, dy: Float,
        anchorRight: Boolean, anchorBottom: Boolean
    ) {
        val origW = orig.width(); val origH = orig.height()
        if (origW < 1f || origH < 1f) return
        val aspect = origW / origH
        val signX = if (anchorRight) -1f else 1f
        val signY = if (anchorBottom) -1f else 1f
        val proj = (signX * dx + signY * dy) / 2f
        var newW = (origW + proj * 2f * (if (signX < 0) -1f else 1f)).coerceAtLeast(MIN_IMAGE_SIZE)
        var newH = newW / aspect
        if (newH < MIN_IMAGE_SIZE) { newH = MIN_IMAGE_SIZE; newW = newH * aspect }
        val aX = if (anchorRight) orig.right else orig.left
        val aY = if (anchorBottom) orig.bottom else orig.top
        val l = if (anchorRight) aX - newW else aX
        val t = if (anchorBottom) aY - newH else aY
        img.rect.set(l, t, l + newW, t + newH)
    }

    fun undo() {
        if (annotationHistory.isEmpty()) return
        when (annotationHistory.removeAt(annotationHistory.size - 1)) {
            AnnotationType.PATH -> if (paths.isNotEmpty()) paths.removeAt(paths.size - 1)
            AnnotationType.HIGHLIGHT -> if (highlights.isNotEmpty()) highlights.removeAt(highlights.size - 1)
            AnnotationType.IMAGE -> {
                if (imageAnnotations.isNotEmpty()) imageAnnotations.removeAt(imageAnnotations.size - 1)
                if (selectedImageIndex >= imageAnnotations.size) {
                    selectedImageIndex = -1; onImageSelectionChanged?.invoke(false)
                }
            }
        }
        invalidate()
    }

    fun clearAnnotations() {
        paths.clear(); highlights.clear(); imageAnnotations.clear(); annotationHistory.clear()
        currentPath = null; currentHighlightRect = null
        selectedImageIndex = -1; dragMode = DragMode.NONE
        onImageSelectionChanged?.invoke(false)
        invalidate()
    }
}
