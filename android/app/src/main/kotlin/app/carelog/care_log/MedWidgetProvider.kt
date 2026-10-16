package app.carelog.care_log

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget listing today's medicines.
 *
 * The Flutter side writes each row's text into the widget storage (see
 * lib/widget_bridge_android.dart). Tapping a row sends `carelog://log?id=…`
 * to a background Dart callback, which logs the dose without opening the app.
 */
class MedWidgetProvider : HomeWidgetProvider() {

    private val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val dotIds = intArrayOf(R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4, R.id.dot5)
    private val nameIds = intArrayOf(R.id.name0, R.id.name1, R.id.name2, R.id.name3, R.id.name4, R.id.name5)
    private val statusIds =
        intArrayOf(R.id.status0, R.id.status1, R.id.status2, R.id.status3, R.id.status4, R.id.status5)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val count = (widgetData.getString("count", "0") ?: "0").toIntOrNull() ?: 0
        val message = widgetData.getString("message", "") ?: ""
        val updated = widgetData.getString("updated", "") ?: ""
        val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        val refresh = HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("carelog://refresh"))

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.med_widget)
            views.setTextViewText(
                R.id.widget_title,
                widgetData.getString("title", null) ?: context.getString(R.string.carelog_widget_title),
            )
            views.setOnClickPendingIntent(R.id.widget_title, openApp)
            views.setOnClickPendingIntent(R.id.widget_refresh, refresh)

            if (count == 0) {
                views.setViewVisibility(R.id.widget_message, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_message,
                    if (message.isEmpty()) "Open Care Log to set up." else message,
                )
                views.setOnClickPendingIntent(R.id.widget_message, openApp)
            } else {
                views.setViewVisibility(R.id.widget_message, View.GONE)
            }

            for (i in rowIds.indices) {
                if (i >= count) {
                    views.setViewVisibility(rowIds[i], View.GONE)
                    continue
                }
                val medId = widgetData.getString("m${i}_id", "") ?: ""
                val color = (widgetData.getString("m${i}_color", "") ?: "").toLongOrNull()?.toInt()
                    ?: 0xFF8A94A0.toInt()
                val taken = widgetData.getString("m${i}_taken", "0") == "1"

                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(nameIds[i], widgetData.getString("m${i}_name", "") ?: "")
                views.setTextViewText(statusIds[i], widgetData.getString("m${i}_status", "") ?: "")
                views.setInt(dotIds[i], "setColorFilter", color)
                views.setInt(
                    rowIds[i],
                    "setBackgroundResource",
                    if (taken) R.drawable.widget_row_taken else R.drawable.widget_row,
                )
                views.setOnClickPendingIntent(
                    rowIds[i],
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("carelog://log?id=" + Uri.encode(medId)),
                    ),
                )
            }

            views.setTextViewText(R.id.widget_footer, updated)
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        // If the data is old (e.g. a dose was logged on another phone while
        // this app was closed), ask the Dart side to reload it. The Dart side
        // stamps `updated_ms` every time, so this can't loop.
        val updatedMs = (widgetData.getString("updated_ms", "0") ?: "0").toLongOrNull() ?: 0L
        if (System.currentTimeMillis() - updatedMs > STALE_AFTER_MS) {
            try {
                refresh.send()
            } catch (e: Exception) {
                // Nothing to do; the next update will try again.
            }
        }
    }

    companion object {
        private const val STALE_AFTER_MS = 15 * 60 * 1000L
    }
}
