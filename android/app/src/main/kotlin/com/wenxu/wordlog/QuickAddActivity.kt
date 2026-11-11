package com.wenxu.wordlog

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** 小组件点击后直接打开的轻量记录页，不启动 Flutter 引擎，秒开 */
class QuickAddActivity : Activity() {

    private lateinit var input: EditText
    private lateinit var ctxInput: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(22), px(20), px(22), px(18))
            setBackgroundColor(Color.WHITE)
        }

        val title = TextView(this).apply {
            text = "记一个词"
            textSize = 14f
            setTextColor(Color.parseColor("#6B7280"))
        }

        input = EditText(this).apply {
            hint = "词或专有名词"
            textSize = 18f
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE
        }

        ctxInput = EditText(this).apply {
            hint = "语境（选填）：在哪看到的"
            textSize = 14f
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE
        }

        val btn = Button(this).apply {
            text = "记下"
            setBackgroundColor(Color.parseColor("#4C6EF5"))
            setTextColor(Color.WHITE)
            setPadding(px(12), px(10), px(12), px(10))
        }

        val btnParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = px(10) }

        root.addView(title)
        root.addView(input, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = px(8) })
        root.addView(ctxInput, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = px(6) })
        root.addView(btn, btnParams)
        root.gravity = Gravity.NO_GRAVITY

        setContentView(root)

        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
        input.requestFocus()

        btn.setOnClickListener { save() }
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                save()
                true
            } else false
        }
        ctxInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                save()
                true
            } else false
        }
    }

    private fun save() {
        val name = input.text.toString().trim()
        if (name.isEmpty()) {
            finish()
            return
        }
        val ctx = ctxInput.text.toString().trim()
        WidgetBridge.addPending(this, name, ctx)
        WidgetBridge.refresh(this)
        Toast.makeText(this, "已记下：$name", Toast.LENGTH_SHORT).show()
        finish()
    }
}
