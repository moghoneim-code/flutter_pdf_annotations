package com.dbs.flutter_pdf_annotations

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.core.content.ContextCompat

// Update ColorPickerDialog.kt
class ColorPickerDialog(context: Context) : Dialog(context) {
    private var onColorSelectedListener: ((Int) -> Unit)? = null

    private val colors = listOf(
        Color.parseColor("#F44336"), // Red
        Color.parseColor("#E91E63"), // Pink
        Color.parseColor("#9C27B0"), // Purple
        Color.parseColor("#673AB7"), // Deep Purple
        Color.parseColor("#3F51B5"), // Indigo
        Color.parseColor("#2196F3"), // Blue
        Color.parseColor("#03A9F4"), // Light Blue
        Color.parseColor("#00BCD4"), // Cyan
        Color.parseColor("#009688"), // Teal
        Color.parseColor("#4CAF50"), // Green
        Color.parseColor("#8BC34A"), // Light Green
        Color.parseColor("#CDDC39"), // Lime
        Color.parseColor("#FFEB3B"), // Yellow
        Color.parseColor("#FFC107"), // Amber
        Color.parseColor("#FF9800"), // Orange
        Color.parseColor("#FF5722"), // Deep Orange
        Color.parseColor("#795548"), // Brown
        Color.parseColor("#9E9E9E"), // Grey
        Color.parseColor("#607D8B"), // Blue Grey
        Color.parseColor("#000000")  // Black
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            setBackgroundColor(Color.WHITE)
        }

        // Add title
        TextView(context).apply {
            text = "Select Color"
            textSize = 20f
            setTextColor(Color.BLACK)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, 24)
            layout.addView(this)
        }

        val gridLayout = GridLayout(context).apply {
            columnCount = 5
            rowCount = 4
            useDefaultMargins = true
        }

        colors.forEach { color ->
            CardView(context).apply {
                layoutParams = GridLayout.LayoutParams().apply {
                    width = 60
                    height = 60
                    setMargins(8, 8, 8, 8)
                }
                radius = 30f
                elevation = 4f

                setCardBackgroundColor(color)
                setOnClickListener {
                    onColorSelectedListener?.invoke(color)
                    dismiss()
                }
            }.also { gridLayout.addView(it) }
        }

        layout.addView(gridLayout)

        setContentView(layout)

        // Set dialog properties
        window?.apply {
            setLayout(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            setBackgroundDrawableResource(android.R.color.transparent)
            decorView.setBackgroundResource(android.R.color.transparent)
        }
    }

    fun setOnColorSelectedListener(listener: (Int) -> Unit) {
        onColorSelectedListener = listener
    }
}