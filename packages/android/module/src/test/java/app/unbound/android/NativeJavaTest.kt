package app.unbound.android

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeJavaTest {
    @Before
    fun resetRegistry() {
        NativeJava.releaseAll()
    }

    private fun handleId(response: String): String = JSONObject(response).getString("id")

    private fun value(response: String): JSONObject = JSONObject(response)

    @Test
    fun getClassReturnsAHandleAndReportsItsName() {
        val handle = NativeJava.getClass("java.lang.StringBuilder")

        assertTrue(handleId(handle).isNotEmpty())
        assertEquals("java.lang.Class", value(NativeJava.className(handle)).getString("value"))
    }

    @Test
    fun getClassRejectsAnUnknownClass() {
        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.getClass("com.example.DoesNotExist")
        }
    }

    @Test
    fun constructAndInvokeRoundTripAStringValue() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")
        val argument = """[{"type":"string","value":"unbound"}]"""

        NativeJava.invoke(builder, "append", argument)

        val result = value(NativeJava.invoke(builder, "toString", "[]"))

        assertEquals("string", result.getString("type"))
        assertEquals("unbound", result.getString("value"))
    }

    @Test
    fun invokeResolvesPrimitiveOverloadsByDeclaredType() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")

        NativeJava.invoke(builder, "append", """[{"type":"int","value":7}]""")

        assertEquals("7", value(NativeJava.invoke(builder, "toString", "[]")).getString("value"))
    }

    @Test
    fun invokeReturnsAHandleForANonSerializableResult() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")
        val result = value(NativeJava.invoke(builder, "append", """[{"type":"string","value":"x"}]"""))

        assertEquals("handle", result.getString("type"))
        assertTrue(result.getString("value").isNotEmpty())
    }

    @Test
    fun invokeCallsAStaticMethodOnAClassHandle() {
        val handle = NativeJava.getClass("java.lang.Integer")
        val result = value(
            NativeJava.invoke(handle, "parseInt", """[{"type":"string","value":"42"}]"""),
        )

        assertEquals("int", result.getString("type"))
        assertEquals(42, result.getInt("value"))
    }

    @Test
    fun invokeReachesClassInstanceMethodsOnAClassHandle() {
        val handle = NativeJava.getClass("java.lang.Integer")

        assertEquals(
            "java.lang.Integer",
            value(NativeJava.invoke(handle, "getName", "[]")).getString("value"),
        )
    }

    @Test
    fun invokeRejectsAMethodThatDoesNotExist() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")

        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.invoke(builder, "noSuchMethod", "[]")
        }
    }

    @Test
    fun respondsToDistinguishesPresentAndAbsentMethods() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")

        assertEquals(
            true,
            value(NativeJava.respondsTo(builder, "toString", "[]")).getBoolean("value"),
        )
        assertEquals(
            false,
            value(NativeJava.respondsTo(builder, "noSuchMethod", "[]")).getBoolean("value"),
        )
    }

    @Test
    fun fieldsReadAndWriteThroughReflection() {
        val point = NativeJava.construct(
            "android.graphics.Point",
            """[{"type":"int","value":3},{"type":"int","value":4}]""",
        )

        assertEquals(3, value(NativeJava.getField(point, "x")).getInt("value"))

        NativeJava.setField(point, "x", """{"type":"int","value":9}""")

        assertEquals(9, value(NativeJava.getField(point, "x")).getInt("value"))
    }

    @Test
    fun getFieldRejectsAFieldThatDoesNotExist() {
        val point = NativeJava.construct("android.graphics.Point", "[]")

        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.getField(point, "noSuchField")
        }
    }

    @Test
    fun nullArgumentsSelectTheDeclaredParameterType() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")
        val argument = """[{"type":"null","class":"java.lang.String"}]"""

        NativeJava.invoke(builder, "append", argument)

        assertEquals("null", value(NativeJava.invoke(builder, "toString", "[]")).getString("value"))
    }

    @Test
    fun arrayArgumentsMarshalByComponentType() {
        val handle = NativeJava.getClass("java.lang.String")
        val argument = """[{"type":"array","componentType":"char","value":["a","b","c"]}]"""
        val result = value(NativeJava.invoke(handle, "valueOf", argument))

        assertEquals("abc", result.getString("value"))
    }

    @Test
    fun handlesAreReleasedIndividuallyAndInBulk() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")

        NativeJava.release(builder)

        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.invoke(builder, "toString", "[]")
        }

        val second = NativeJava.construct("java.lang.StringBuilder", "[]")
        NativeJava.releaseAll()

        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.invoke(second, "toString", "[]")
        }
    }

    @Test
    fun handlesAreStableForTheSameObject() {
        val handle = NativeJava.getClass("java.lang.Integer")

        assertEquals(handleId(handle), handleId(NativeJava.getClass("java.lang.Integer")))
        assertNotEquals(handleId(handle), handleId(NativeJava.getClass("java.lang.Long")))
    }

    @Test
    fun invokeRejectsAnUnboundedArgumentCount() {
        val builder = NativeJava.construct("java.lang.StringBuilder", "[]")
        val arguments = (1..64).joinToString(",", "[", "]") { """{"type":"int","value":$it}""" }

        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.invoke(builder, "append", arguments)
        }
    }

    @Test
    fun classNamesAreLengthBounded() {
        assertThrows(IllegalArgumentException::class.java) {
            NativeJava.getClass("a".repeat(512))
        }
    }
}
