package com.wenxu.wordlog

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

object WidgetBridge {

    private fun prefs(context: Context) =
        context.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)

    /** 把小组件或快捷入口记下的词暂存起来，等 App 启动时收进数据库 */
    fun addPending(context: Context, name: String, ctx: String) {
        val p = prefs(context)
        val arr = try {
            JSONArray(p.getString(MainActivity.KEY_PENDING, "[]") ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        val o = JSONObject()
        o.put("name", name)
        o.put("context", ctx)
        o.put("ts", System.currentTimeMillis())
        arr.put(o)
        p.edit().putString(MainActivity.KEY_PENDING, arr.toString()).apply()

        // 让小组件立刻有反馈（真实数量由 App 下次启动校正）
        val recent = p.getString(MainActivity.KEY_RECENT, "") ?: ""
        val merged = (if (recent.isBlank()) "" else "$recent\n") + name
        val trimmed = merged.split("\n").takeLast(3).joinToString("\n")
        p.edit()
            .putString(MainActivity.KEY_RECENT, trimmed)
            .putInt(MainActivity.KEY_COUNT, p.getInt(MainActivity.KEY_COUNT, 0) + 1)
            .apply()
    }

    fun refresh(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val cn = ComponentName(context, WordWidgetProvider::class.java)
        val ids = mgr.getAppWidgetIds(cn)
        if (ids.isEmpty()) return
        val intent = Intent(context, WordWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }
}
