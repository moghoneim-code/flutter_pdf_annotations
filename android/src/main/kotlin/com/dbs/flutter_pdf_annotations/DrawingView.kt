package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
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

    data class AnnotationData(val path: Path, val strokeWidth: Float, val color: Int)
    data class HighlightAnnotationData(val rect: RectF, val color: Int)
    data class ImageAnnotationData(val bitmap: Bitmap, var rect: RectF)

    enum class AnnotationType { PATH, HIGHLIGHT, IMAGE }
    private enum class DragMode { NONE, MOVE, TL, TR, BL, BR }

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

    private fun handleRadiusPdf(): Float = 16f / matrixScaleX()

    fun getAnnotations(): List<AnnotationData> = paths.toList()
    fun getHighlights(): List<HighlightAnnotationData> = highlights.toList()
    fun getImageAnnotations(): List<ImageAnnotationData> = imageAnnotations.toList()
    fun hasSelectedImage(): Boolean = selectedImageIndex >= 0

    fun placeImage(bitmap: Bitmap, cx: Float, cy: Float) {
        val refWidth = if (pageBitmapWidth > 0) pageBitmapWidth else width.toFloat()
        val imgW = refWidth * 0.4f
        val imgH = imgW * bitmap.height.toFloat() / bitmap.width.toFloat()
        val rect = RectF(cx - imgW / 2, cy - imgH / 2, cx + imgW / 2, cy + imgH / 2)
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

    /** Deselect (keep the image). Called by the Accept button in the activity. */
    fun acceptSelectedImage() {
        selectedImageIndex = -1
        dragMode = DragMode.NONE
        onImageSelectionChanged?.invoke(false)
        invalidate()
    }

    /** Delete the selected image. Called by the Delete button in the activity. */
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

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.concat(matrix)

        // Highlights
        val highlightPaint = Paint().apply { style = Paint.Style.FILL }
        highlights.forEach { h -> highlightPaint.color = h.color; canvas.drawRect(h.rect, highlightPaint) }
        currentHighlightRect?.let { canvas.drawRect(it, Paint().apply { style = Paint.Style.FILL; color = highlightColor }) }

        // Images
        val r = handleRadiusPdf()
        val scale = matrixScaleX()
        imageAnnotations.forEachIndexed { idx, img ->
            canvas.drawBitmap(img.bitmap, null, img.rect, null)
            if (idx == selectedImageIndex) {
                // Dashed blue border
                canvas.drawRect(img.rect, Paint().apply {
                    style = Paint.Style.STROKE
                    color = Color.parseColor("#2196F3")
                    strokeWidth = 2f / scale
                    pathEffect = DashPathEffect(floatArrayOf(8f / scale, 4f / scale), 0f)
                    isAntiAlias = true
                })
                // 4 corner resize handles (white circle + blue ring)
                val fill = Paint().apply { style = Paint.Style.FILL; color = Color.WHITE; isAntiAlias = true }
                val stroke = Paint().apply {
                    style = Paint.Style.STROKE; color = Color.parseColor("#2196F3")
                    strokeWidth = 2f / scale; isAntiAlias = true
                }
                for (pt in cornerPoints(img.rect)) {
                    canvas.drawCircle(pt.x, pt.y, r, fill)
                    canvas.drawCircle(pt.x, pt.y, r, stroke)
                }
            }
        }

        // Paths
        paths.forEach { a -> paint.color = a.color; paint.strokeWidth = a.strokeWidth; canvas.drawPath(a.path, paint) }
        currentPath?.let { canvas.drawPath(it, paint) }

        canvas.restore()
    }

    private fun cornerPoints(rect: RectF) = listOf(
        PointF(rect.left, rect.top),
        PointF(rect.right, rect.top),
        PointF(rect.left, rect.bottom),
        PointF(rect.right, rect.bottom)
    )

    private fun dist(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x1 - x2; val dy = y1 - y2
        return Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false
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
        val r = handleRadiusPdf() * 3f   // generous hit area so corners are easy to grab
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                if (selectedImageIndex >= 0) {
                    val img = imageAnnotations.getOrNull(selectedImageIndex) ?: return false
                    val corners = cornerPoints(img.rect)
                    val modes = listOf(DragMode.TL, DragMode.TR, DragMode.BL, DragMode.BR)
                    for ((i, pt) in corners.withIndex()) {
                        if (dist(x, y, pt.x, pt.y) <= r) {
                            dragMode = modes[i]; dragStart.set(x, y); dragOrigRect = RectF(img.rect); return true
                        }
                    }
                    if (img.rect.contains(x, y)) {
                        dragMode = DragMode.MOVE; dragStart.set(x, y); dragOrigRect = RectF(img.rect); return true
                    }
                    // Tapped outside selected image → deselect
                    selectedImageIndex = -1
                    onImageSelectionChanged?.invoke(false)
                    invalidate(); return true
                }
                // Hit-test for selection
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
                val min = 20f
                when (dragMode) {
                    DragMode.MOVE -> img.rect.set(orig.left + dx, orig.top + dy, orig.right + dx, orig.bottom + dy)
                    DragMode.TL -> img.rect.set(minOf(orig.left + dx, orig.right - min), minOf(orig.top + dy, orig.bottom - min), orig.right, orig.bottom)
                    DragMode.TR -> img.rect.set(orig.left, minOf(orig.top + dy, orig.bottom - min), maxOf(orig.right + dx, orig.left + min), orig.bottom)
                    DragMode.BL -> img.rect.set(minOf(orig.left + dx, orig.right - min), orig.top, orig.right, maxOf(orig.bottom + dy, orig.top + min))
                    DragMode.BR -> img.rect.set(orig.left, orig.top, maxOf(orig.right + dx, orig.left + min), maxOf(orig.bottom + dy, orig.top + min))
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

    fun undo() {
        if (annotationHistory.isEmpty()) return
        when (annotationHistory.removeAt(annotationHistory.size - 1)) {
            AnnotationType.PATH -> if (paths.isNotEmpty()) paths.removeAt(paths.size - 1)
            AnnotationType.HIGHLIGHT -> if (highlights.isNotEmpty()) highlights.removeAt(highlights.size - 1)
            AnnotationType.IMAGE -> {
                if (imageAnnotations.isNotEmpty()) imageAnnotations.removeAt(imageAnnotations.size - 1)
                if (selectedImageIndex >= imageAnnotations.size) {
                    selectedImageIndex = -1
                    onImageSelectionChanged?.invoke(false)
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
