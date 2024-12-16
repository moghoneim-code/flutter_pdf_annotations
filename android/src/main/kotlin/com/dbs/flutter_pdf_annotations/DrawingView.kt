package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View

class DrawingView(context: Context) : View(context) {
    private val paint = Paint().apply {
        isAntiAlias = true
        strokeWidth = 5f
        color = Color.RED
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
    }

    private var originalBitmap: Bitmap? = null
    private var annotationBitmap: Bitmap? = null
    private var canvas: Canvas? = null

    private var viewWidth = 0
    private var viewHeight = 0
    private var bitmapWidth = 0
    private var bitmapHeight = 0

    private val paths = mutableListOf<PathData>()
    private var currentPath = Path()
    private var isDrawing = false

    // Data class to store path and its paint properties
    data class PathData(val path: Path, val paint: Paint)

    fun setBitmap(bitmap: Bitmap) {
        originalBitmap = bitmap
        bitmapWidth = bitmap.width
        bitmapHeight = bitmap.height
        annotationBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        canvas = Canvas(annotationBitmap!!)
        invalidate()
    }

    fun getAnnotatedBitmap(): Bitmap? = annotationBitmap

    fun clearAnnotations() {
        annotationBitmap = originalBitmap?.copy(Bitmap.Config.ARGB_8888, true)
        canvas = Canvas(annotationBitmap!!)
        paths.clear()
        currentPath.reset()
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        viewWidth = w
        viewHeight = h
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // Draw the PDF bitmap
        annotationBitmap?.let { bitmap ->
            // Calculate scaling to maintain aspect ratio
            val scale = calculateScaleToFit()
            val scaledWidth = bitmapWidth * scale
            val scaledHeight = bitmapHeight * scale

            // Calculate offsets to center the image
            val left = (viewWidth - scaledWidth) / 2f
            val top = (viewHeight - scaledHeight) / 2f

            // Draw bitmap with calculated scaling
            val destRect = RectF(left, top, left + scaledWidth, top + scaledHeight)
            canvas.drawBitmap(bitmap, null, destRect, null)

            // Draw saved paths
            paths.forEach { pathData ->
                canvas.save()
                canvas.translate(left, top)
                canvas.scale(scale, scale)
                canvas.drawPath(pathData.path, pathData.paint)
                canvas.restore()
            }

            // Draw the current path if drawing
            if (isDrawing) {
                canvas.save()
                canvas.translate(left, top)
                canvas.scale(scale, scale)
                canvas.drawPath(currentPath, paint)
                canvas.restore()
            }
        }
    }

    private fun calculateScaleToFit(): Float {
        val scaleX = viewWidth.toFloat() / bitmapWidth
        val scaleY = viewHeight.toFloat() / bitmapHeight
        return minOf(scaleX, scaleY)
    }

    private fun mapTouchCoordinates(x: Float, y: Float): PointF {
        // Calculate scaling
        val scale = calculateScaleToFit()

        // Calculate offsets to center the image
        val scaledWidth = bitmapWidth * scale
        val scaledHeight = bitmapHeight * scale
        val left = (viewWidth - scaledWidth) / 2f
        val top = (viewHeight - scaledHeight) / 2f

        // Map touch coordinates to bitmap coordinates
        val mappedX = (x - left) / scale
        val mappedY = (y - top) / scale

        return PointF(mappedX, mappedY)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Check if no bitmap is set
        if (annotationBitmap == null) return false

        val mappedPoint = mapTouchCoordinates(event.x, event.y)
        val x = mappedPoint.x
        val y = mappedPoint.y

        // Check if touch is within bitmap bounds
        if (x < 0 || x > bitmapWidth || y < 0 || y > bitmapHeight) {
            return false
        }

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                currentPath = Path()
                currentPath.moveTo(x, y)
                isDrawing = true
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                currentPath.lineTo(x, y)
                invalidate()
            }
            MotionEvent.ACTION_UP -> {
                // Save the completed path
                paths.add(PathData(currentPath, Paint(paint)))

                // Draw the path onto the annotation bitmap
                canvas?.let {
                    it.drawPath(currentPath, paint)
                }

                isDrawing = false
                invalidate()
            }
        }
        return true
    }
}