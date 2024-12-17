package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import android.util.DisplayMetrics
import android.view.WindowInsets

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
    private var pageWidth = 0
    private var pageHeight = 0
    private var pdfViewBounds = RectF()
    private var matrix = Matrix()
    private var inverseMatrix = Matrix()
    private var originalStrokeWidth = 5f

    data class AnnotationData(
        val path: Path,
        val strokeWidth: Float,
        val color: Int
    )

    fun setColor(color: Int) {
        paint = Paint(paint).apply {
            this.color = color
        }
    }

    fun setStrokeWidth(width: Float) {
        originalStrokeWidth = width
        updatePaintStrokeWidth()
    }

    private fun updatePaintStrokeWidth() {
        // Scale stroke width based on PDF to view ratio
        val scaleFactor = getScaleFactor()
        paint.strokeWidth = originalStrokeWidth / scaleFactor
    }

    private fun getScaleFactor(): Float {
        // Calculate actual scale factor between PDF and view coordinates
        return if (pageWidth > 0 && pdfViewBounds.width() > 0) {
            pdfViewBounds.width() / pageWidth
        } else 1f
    }

    fun setPdfViewBounds(bounds: RectF) {
        pdfViewBounds = bounds
        updateMatrix()
    }

    fun setPageSize(width: Int, height: Int) {
        pageWidth = width
        pageHeight = height
        updateMatrix()
        updatePaintStrokeWidth()
    }

    private fun updateMatrix() {
        if (pageWidth <= 0 || pageHeight <= 0 || pdfViewBounds.isEmpty) return

        matrix.reset()

        // Calculate visible content bounds
        val contentWidth = pdfViewBounds.width()
        val contentHeight = pdfViewBounds.height()

        // Calculate scale to fit the page
        val scaleX = contentWidth / pageWidth
        val scaleY = contentHeight / pageHeight
        val scale = Math.min(scaleX, scaleY)

        // Calculate centering offsets
        val translateX = pdfViewBounds.left + (contentWidth - pageWidth * scale) / 2f
        val translateY = pdfViewBounds.top + (contentHeight - pageHeight * scale) / 2f

        matrix.setScale(scale, scale)
        matrix.postTranslate(translateX, translateY)
        matrix.invert(inverseMatrix)
    }
    fun getPaths(): List<Path> {
        return paths.map { it.path }
    }

    fun getAnnotations(): List<AnnotationData> = paths.toList()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        canvas.save()
        canvas.concat(matrix)

        // Draw all paths
        paths.forEach { annotationData ->
            paint.color = annotationData.color
            paint.strokeWidth = annotationData.strokeWidth
            canvas.drawPath(annotationData.path, paint)
        }

        // Draw current path
        currentPath?.let {
            canvas.drawPath(it, paint)
        }

        canvas.restore()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false

        // Transform touch coordinates to PDF coordinates
        val points = floatArrayOf(event.x, event.y)
        inverseMatrix.mapPoints(points)
        val x = points[0]
        val y = points[1]

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                currentPath = Path().apply {
                    moveTo(x, y)
                }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                currentPath?.lineTo(x, y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                currentPath?.let {
                    paths.add(AnnotationData(
                        path = it,
                        strokeWidth = paint.strokeWidth,
                        color = paint.color
                    ))
                }
                currentPath = null
                invalidate()
                return true
            }
            else -> return false
        }
    }

    fun undo() {
        if (paths.isNotEmpty()) {
            paths.removeAt(paths.size - 1)
            invalidate()
        }
    }

    fun clearAnnotations() {
        paths.clear()
        currentPath = null
        invalidate()
    }
}