package app.carelog.care_log

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin

/** Supplies the rows of the medicines widget's scrolling list. */
class MedWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        MedRowsFactory(applicationContext)
}

private class MedRowsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private data class Row(
        val id: String,
        val name: String,
        val status: String,
        val taken: String,
        val color: Int,
    )

    private var rows: List<Row> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val data = HomeWidgetPlugin.getData(context)
        val count = (data.getString("count", "0") ?: "0").toIntOrNull() ?: 0
        rows = (0 until count).map { i ->
            Row(
                id = data.getString("m${i}_id", "") ?: "",
                name = data.getString("m${i}_name", "") ?: "",
                status = data.getString("m${i}_status", "") ?: "",
                taken = data.getString("m${i}_taken", "0") ?: "0",
                color = (data.getString("m${i}_color", "") ?: "").toLongOrNull()?.toInt()
                    ?: 0xFF8A94A0.toInt(),
            )
        }
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.med_widget_row)
        val row = rows.getOrNull(position) ?: return views
        views.setTextViewText(R.id.row_name, row.name)
        views.setTextViewText(R.id.row_status, row.status)
        views.setInt(R.id.row_dot, "setColorFilter", row.color)
        views.setInt(
            R.id.row_root,
            "setBackgroundResource",
            when (row.taken) {
                "1" -> R.drawable.widget_row_taken
                "part" -> R.drawable.widget_row_partial
                else -> R.drawable.widget_row
            },
        )
        val fill = Intent().apply { data = Uri.parse("carelog://log?id=" + Uri.encode(row.id)) }
        views.setOnClickFillInIntent(R.id.row_root, fill)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
