package app.unbound.android

import android.app.Activity
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeUITest {
    @Test
    fun lookupReturnsHandlesForMatchingViewsWithinTheResultLimit() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val container = LinearLayout(activity)
        container.addView(TextView(activity).apply { text = "First" })
        container.addView(TextView(activity).apply { text = "Second" })
        activity.setContentView(container)
        ActivityTracker.onActivityResumed(activity)

        val response = JSONArray(NativeUI.lookup("""{"role":"text","maxResults":1}"""))

        assertEquals(1, response.length())
        assertEquals(true, response.getJSONObject(0).getString("id").isNotEmpty())
    }

    @Test
    fun snapshotReturnsTextAndGenerationScopedParentHandles() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val container = LinearLayout(activity)
        val label = TextView(activity).apply { text = "Target message" }
        container.addView(label)
        activity.setContentView(container)
        ActivityTracker.onActivityResumed(activity)

        val handle = JSONArray(NativeUI.lookup("""{"role":"text"}""")).getJSONObject(0)
        val snapshot = JSONObject(
            NativeUI.snapshot("""{"role":"text","root":${handle}}"""),
        )
        val node = snapshot.getJSONArray("nodes").getJSONObject(0)

        assertEquals(ActivityTracker.generation, snapshot.getLong("generation"))
        assertEquals("Target message", node.getJSONObject("attributes").getString("text"))
        assertEquals(handle.getString("id"), node.getJSONObject("id").getString("id"))
    }

    @Test
    fun snapshotRejectsAHandleFromAnEarlierActivityGeneration() {
        val firstActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        firstActivity.setContentView(TextView(firstActivity).apply { text = "First" })
        ActivityTracker.onActivityResumed(firstActivity)
        val handle = JSONArray(NativeUI.lookup("""{"role":"text"}""")).getJSONObject(0)

        val secondActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        secondActivity.setContentView(TextView(secondActivity).apply { text = "Second" })
        ActivityTracker.onActivityResumed(secondActivity)

        assertThrows(IllegalArgumentException::class.java) {
            NativeUI.snapshot("""{"role":"text","root":${handle}}""")
        }
    }
}
