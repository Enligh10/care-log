package app.carelog.care_log

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget listing today's medicines in a scrolling list.
 *
 * The Flutter side writes each row's text into the widget storage (see
 * lib/widget_bridge_android.dart); [MedWidgetService] turns those into list
 * rows. Tapping a row sends `carelog://log?id=…` to a background Dart
 * callback, which logs the dose without opening the app.
 */
class MedWidgetProvider : HomeWidgetProvider() {

    @Suppress("DEPRECATION")
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
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

            // Shown by the list when it has no rows.
            views.setTextViewText(
                R.id.widget_message,
                if (message.isEmpty()) "Open Care Log to set up." else message,
            )
            views.setOnClickPendingIntent(R.id.widget_message, openApp)

            // The scrolling list of medicines.
            val listIntent = Intent(context, MedWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.med_list, listIntent)
            views.setEmptyView(R.id.med_list, R.id.widget_message)
            views.setPendingIntentTemplate(R.id.med_list, logTemplate(context))

            views.setTextViewText(R.id.widget_footer, updated)
            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.med_list)
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

    /**
     * Template for row taps. Each row fills in its own `carelog://log?id=…`
     * data, so this must be mutable (it is explicit, so that's allowed).
     */
    private fun logTemplate(context: Context): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getBroadcast(context, 1, intent, flags)
    }

    companion object {
        private const val STALE_AFTER_MS = 15 * 60 * 1000L
    }
}
