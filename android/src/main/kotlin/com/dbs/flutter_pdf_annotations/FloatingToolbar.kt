package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.MotionEvent
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.ImageButton
import androidx.cardview.widget.CardView

class FloatingToolbar(context: Context) : CardView(context) {
    var onDrawingToggled: ((Boolean) -> Unit)? = null
    var onColorSelected: ((Int) -> Unit)? = null
    var onStrokeWidthChanged: ((Float) -> Unit)? = null
    var onUndoClicked: (() -> Unit)? = null
    var onClearClicked: (() -> Unit)? = null

    private var isDrawingMode = false
    private var isDragging = false
    private var lastX = 0f
    private var lastY = 0f

    init {
        radius = 16f
        elevation = 8f

        val toolbarLayout = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(16, 8, 16, 8)
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.WHITE)
        }

        addButtons(toolbarLayout)

        addView(toolbarLayout)
        setupDragging()

        // Set initial position
        x = 50f
        y = 50f
    }

    private fun addButtons(layout: LinearLayout) {
        // Drawing toggle
        createImageButton(android.R.drawable.ic_menu_edit).apply {
            setOnClickListener {
                isDrawingMode = !isDrawingMode
                setColorFilter(if (isDrawingMode) Color.RED else Color.BLACK)
                onDrawingToggled?.invoke(isDrawingMode)
            }
            layout.addView(this)
        }

        // Color picker
        createImageButton(android.R.drawable.ic_menu_gallery).apply {
            setOnClickListener { showColorPicker() }
            layout.addView(this)
        }

        // Stroke width
        SeekBar(context).apply {
            layoutParams = LinearLayout.LayoutParams(200, LinearLayout.LayoutParams.WRAP_CONTENT)
            max = 50
            progress = 5
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    onStrokeWidthChanged?.invoke(progress.toFloat())
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {}
            })
            layout.addView(this)
        }

        // Undo button
        createImageButton(android.R.drawable.ic_menu_revert).apply {
            setOnClickListener { onUndoClicked?.invoke() }
            layout.addView(this)
        }

        // Clear button
        createImageButton(android.R.drawable.ic_menu_delete).apply {
            setOnClickListener { onClearClicked?.invoke() }
            layout.addView(this)
        }
    }

    private fun createImageButton(iconRes: Int): ImageButton =
        ImageButton(context).apply {
            setImageResource(iconRes)
            background = null
            setPadding(8, 8, 8, 8)
        }

    private fun setupDragging() {
        var startClickTime: Long = 0
        val clickDuration = 200

        setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDragging = true
                    startClickTime = System.currentTimeMillis()
                    lastX = event.rawX
                    lastY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (isDragging) {
                        val dx = event.rawX - lastX
                        val dy = event.rawY - lastY
                        if (Math.abs(dx) > 5 || Math.abs(dy) > 5) {
                            x += dx
                            y += dy
                            lastX = event.rawX
                            lastY = event.rawY
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val clickTime = System.currentTimeMillis() - startClickTime
                    if (clickTime < clickDuration) {
                        view.performClick()
                    }
                    isDragging = false
                    true
                }
                else -> false
            }
        }
    }

    private fun showColorPicker() {
        val colors = listOf(
            Color.RED,
            Color.BLUE,
            Color.GREEN,
            Color.BLACK,
            Color.MAGENTA
        )
        onColorSelected?.invoke(colors.random())
    }
}