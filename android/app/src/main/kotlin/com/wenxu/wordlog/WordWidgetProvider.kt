package com.wenxu.wordlog

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class WordWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            update(context, appWidgetManager, id)
        }
    }

    private fun update(context: Context, mgr: AppWidgetManager, id: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_word)
        val p = context.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)
        val count = p.getInt(MainActivity.KEY_COUNT, 0)
        val recent = p.getString(MainActivity.KEY_RECENT, "") ?: ""

        views.setTextViewText(R.id.widget_count, count.toString())
        views.setTextViewText(
            R.id.widget_recent,
            if (recent.isBlank()) "点这里记一个词" else recent.replace("\n", " · ")
        )

        val intent = Intent(context, QuickAddActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_root, pi)

        mgr.updateAppWidget(id, views)
    }
}
