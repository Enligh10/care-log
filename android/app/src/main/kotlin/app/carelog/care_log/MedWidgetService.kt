package app.carelog.care_log

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
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

    /** Text sizes (sp) and vertical padding (dp) for each widget size. */
    private data class Look(val dot: Float, val name: Float, val status: Float, val padV: Int, val tall: Boolean)

    private val looks = listOf(
        Look(dot = 9f, name = 12f, status = 11f, padV = 6, tall = false),
        Look(dot = 11f, name = 14f, status = 12f, padV = 11, tall = false),
        Look(dot = 15f, name = 18f, status = 15f, padV = 12, tall = true),
        Look(dot = 19f, name = 23f, status = 19f, padV = 16, tall = true),
    )

    private var rows: List<Row> = emptyList()
    private var look: Look = looks[MedWidgetProvider.DEFAULT_SIZE]

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val data = HomeWidgetPlugin.getData(context)
        val count = (data.getString("count", "0") ?: "0").toIntOrNull() ?: 0
        val size = (data.getString("size", null) ?: "${MedWidgetProvider.DEFAULT_SIZE}").toIntOrNull()
            ?: MedWidgetProvider.DEFAULT_SIZE
        look = looks[size.coerceIn(0, looks.size - 1)]
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
        val l = look
        val views = RemoteViews(
            context.packageName,
            if (l.tall) R.layout.med_widget_row_tall else R.layout.med_widget_row,
        )
        val row = rows.getOrNull(position) ?: return views
        views.setTextViewText(R.id.row_name, row.name)
        views.setTextViewText(R.id.row_status, row.status)
        views.setTextColor(R.id.row_dot, row.color)
        views.setTextViewTextSize(R.id.row_dot, TypedValue.COMPLEX_UNIT_SP, l.dot)
        views.setTextViewTextSize(R.id.row_name, TypedValue.COMPLEX_UNIT_SP, l.name)
        views.setTextViewTextSize(R.id.row_status, TypedValue.COMPLEX_UNIT_SP, l.status)
        views.setInt(
            R.id.row_root,
            "setBackgroundResource",
            when (row.taken) {
                "1" -> R.drawable.widget_row_taken
                "part" -> R.drawable.widget_row_partial
                else -> R.drawable.widget_row
            },
        )
        // Padding goes after the background so the new background can't reset it.
        val px = { dp: Int -> (dp * context.resources.displayMetrics.density).toInt() }
        val padH = if (l.tall) 14 else 12
        views.setViewPadding(R.id.row_root, px(padH), px(l.padV), px(padH), px(l.padV))
        val fill = Intent().apply { data = Uri.parse("carelog://log?id=" + Uri.encode(row.id)) }
        views.setOnClickFillInIntent(R.id.row_root, fill)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
