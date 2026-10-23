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

    @Test
    fun measureReturnsTheCurrentLaidOutFrame() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val label = TextView(activity).apply { text = "Measured" }
        activity.setContentView(label)
        ActivityTracker.onActivityResumed(activity)
        label.layout(0, 0, 120, 40)
        val handle = JSONArray(NativeUI.lookup("""{"role":"text"}""")).getJSONObject(0)

        val measured = JSONObject(NativeUI.measureView(handle.toString()))

        assertEquals(120.0, measured.getDouble("width"), 0.0)
        assertEquals(40.0, measured.getDouble("height"), 0.0)
    }

    @Test
    fun measureRejectsAHandleFromAnEarlierActivityGeneration() {
        val firstActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        firstActivity.setContentView(TextView(firstActivity).apply { text = "First" })
        ActivityTracker.onActivityResumed(firstActivity)
        val handle = JSONArray(NativeUI.lookup("""{"role":"text"}""")).getJSONObject(0)

        val secondActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        secondActivity.setContentView(TextView(secondActivity).apply { text = "Second" })
        ActivityTracker.onActivityResumed(secondActivity)

        assertThrows(IllegalArgumentException::class.java) {
            NativeUI.measureView(handle.toString())
        }
    }

    @Test
    fun frameUpdateValidatesAndAppliesBoundedDimensions() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val label = TextView(activity).apply { text = "Resizable" }
        activity.setContentView(label)
        ActivityTracker.onActivityResumed(activity)
        val handle = JSONArray(NativeUI.lookup("""{"role":"text"}""")).getJSONObject(0)

        NativeUI.setViewFrame(
            handle.toString(),
            """{"x":20,"y":30,"width":80,"height":24}""",
        )

        assertEquals(80, label.layoutParams.width)
        assertEquals(24, label.layoutParams.height)
        assertThrows(IllegalArgumentException::class.java) {
            NativeUI.setViewFrame(handle.toString(), """{"x":0,"y":0,"width":0,"height":24}""")
        }
    }

    @Test
    fun activityTrackerClearsPausedActivitiesAndTracksTheNextResume() {
        val firstActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        ActivityTracker.onActivityResumed(firstActivity)
        val firstGeneration = ActivityTracker.generation

        ActivityTracker.onActivityPaused(firstActivity)

        assertEquals(null, ActivityTracker.currentActivity())

        val secondActivity = Robolectric.buildActivity(Activity::class.java).setup().get()
        ActivityTracker.onActivityResumed(secondActivity)

        assertEquals(secondActivity, ActivityTracker.currentActivity())
        assertEquals(firstGeneration + 1, ActivityTracker.generation)
        ActivityTracker.onActivityPaused(secondActivity)
    }
}
