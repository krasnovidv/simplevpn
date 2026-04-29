package com.simplevpn.app

import com.simplevpn.app.SimpleVpnService.Companion.calculateBackoff
import com.simplevpn.app.SimpleVpnService.Companion.decideRetry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the retry-policy logic introduced in Phase 4 Task 3.
 *
 * Tests run in pure JVM (`./gradlew :app:testDebugUnitTest`) — no Android
 * framework, no Robolectric, no Vpnlib stubbing required because the policy
 * was extracted into the pure [SimpleVpnService.decideRetry] helper.
 */
class SimpleVpnServiceTest {

    // -------- calculateBackoff --------------------------------------------

    @Test
    fun calculateBackoff_followsExponentialUntilCap() {
        // attempt -> expected ms with default 60s cap.
        // Formula: (1L shl attempt) * 1000, capped at maxBackoffSeconds * 1000.
        // attempt=1 → 2^1*1s = 2s, attempt=6 → 64s capped to 60s, etc.
        val expected = listOf(
            0 to 1000L,        // attempt<=0 floor
            1 to 2000L,        // 2^1 * 1s
            2 to 4000L,
            3 to 8000L,
            4 to 16_000L,
            5 to 32_000L,
            6 to 60_000L,      // would be 64s, capped to 60s
            7 to 60_000L,
            8 to 60_000L,
            9 to 60_000L,
            10 to 60_000L,
        )
        for ((attempt, want) in expected) {
            val got = calculateBackoff(attempt, 60)
            assertEquals("attempt=$attempt", want, got)
        }
    }

    @Test
    fun calculateBackoff_respectsCustomCap() {
        // With 10s cap, 4th attempt (16s) should already be capped.
        assertEquals(2000L, calculateBackoff(1, 10))
        assertEquals(4000L, calculateBackoff(2, 10))
        assertEquals(8000L, calculateBackoff(3, 10))
        assertEquals(10_000L, calculateBackoff(4, 10)) // 16s capped to 10s
        assertEquals(10_000L, calculateBackoff(20, 10))
    }

    @Test
    fun calculateBackoff_handlesNegativeAttempt() {
        assertEquals(1000L, calculateBackoff(-1, 60))
        assertEquals(1000L, calculateBackoff(Int.MIN_VALUE, 60))
    }

    @Test
    fun calculateBackoff_doesNotOverflow() {
        // Very large attempt should not panic — clamp to cap.
        assertEquals(60_000L, calculateBackoff(1000, 60))
        assertEquals(60_000L, calculateBackoff(Int.MAX_VALUE, 60))
    }

    // -------- decideRetry: short-circuits ---------------------------------

    @Test
    fun decideRetry_authShortCircuitsImmediately() {
        // First-ever attempt sees auth: must NOT retry, must latch, must surface error.
        val d = decideRetry(
            autoReconnect = true,
            retryStopped = false,
            kind = "auth",
            currentAttempt = 0,
            maxRetries = 5,
            maxBackoffSeconds = 60,
        )
        assertFalse("auth must not retry", d.shouldRetry)
        assertTrue("auth must latch retryStopped", d.latchStopped)
        assertEquals("error: auth rejected", d.statusOverride)
        assertEquals("auth-rejected", d.reason)
    }

    @Test
    fun decideRetry_authNeverAdvancesCounter() {
        // Even at attempt=3 (well below max), auth must short-circuit and NOT
        // increment the attempt counter — guards against the "retry counter
        // does not advance on auth" device test in PHASE4_TEST_PLAN.md.
        val d = decideRetry(true, false, "auth", 3, 10, 60)
        assertFalse(d.shouldRetry)
        assertEquals(3, d.nextAttempt)
    }

    @Test
    fun decideRetry_fatalShortCircuits() {
        val d = decideRetry(true, false, "fatal", 0, 5, 60)
        assertFalse(d.shouldRetry)
        assertTrue(d.latchStopped)
        assertEquals("fatal", d.reason)
    }

    @Test
    fun decideRetry_noneIsCleanDisconnect() {
        // User pressed Disconnect → kind=none → no retry, no latch.
        val d = decideRetry(true, false, "none", 2, 5, 60)
        assertFalse(d.shouldRetry)
        assertFalse("clean disconnect must not latch the loop off", d.latchStopped)
        assertEquals("clean-disconnect", d.reason)
    }

    @Test
    fun decideRetry_autoReconnectDisabledNeverRetries() {
        val d = decideRetry(false, false, "transient", 0, 5, 60)
        assertFalse(d.shouldRetry)
        assertEquals("auto-reconnect-disabled", d.reason)
    }

    @Test
    fun decideRetry_alreadyStoppedNeverRetries() {
        val d = decideRetry(true, true, "transient", 1, 5, 60)
        assertFalse(d.shouldRetry)
        assertTrue(d.latchStopped)
        assertEquals("already-stopped", d.reason)
    }

    // -------- decideRetry: transient retries ------------------------------

    @Test
    fun decideRetry_transientRetriesUpToMax() {
        // currentAttempt=0..4 with maxRetries=5: all should retry, advancing 1..5.
        for (current in 0..4) {
            val d = decideRetry(true, false, "transient", current, 5, 60)
            assertTrue("attempt $current should retry", d.shouldRetry)
            assertEquals(current + 1, d.nextAttempt)
            assertFalse(d.latchStopped)
            assertEquals("connecting (retry ${current + 1}/5)", d.statusOverride)
        }
    }

    @Test
    fun decideRetry_transientStopsAtMax() {
        // currentAttempt=5, maxRetries=5 → next would be 6 > 5 → stop.
        val d = decideRetry(true, false, "transient", 5, 5, 60)
        assertFalse(d.shouldRetry)
        assertTrue(d.latchStopped)
        assertEquals("error: max retries exceeded", d.statusOverride)
        assertEquals("max-retries-exceeded", d.reason)
    }

    @Test
    fun decideRetry_unlimitedRetriesNeverHitMax() {
        val d = decideRetry(true, false, "transient", 1_000_000, Int.MAX_VALUE, 60)
        assertTrue(d.shouldRetry)
        assertEquals(1_000_001, d.nextAttempt)
        // Backoff should be capped, never overflow.
        assertEquals(60_000L, d.delayMs)
    }

    @Test
    fun decideRetry_unknownKindTreatedAsTransient() {
        val d = decideRetry(true, false, "unrecognized-kind", 0, 5, 60)
        assertTrue(d.shouldRetry)
        assertEquals(1, d.nextAttempt)
    }

    @Test
    fun decideRetry_immediateZerosTheDelay() {
        val d = decideRetry(true, false, "transient", 3, 5, 60, immediate = true)
        assertTrue(d.shouldRetry)
        assertEquals(0L, d.delayMs)
        assertEquals(4, d.nextAttempt)
    }

    @Test
    fun decideRetry_backoffMatchesCalculateBackoff() {
        // Sanity: decideRetry should delegate to calculateBackoff for the delay.
        val d = decideRetry(true, false, "transient", 2, 10, 60)
        // nextAttempt = 3 → calculateBackoff(3, 60) = 8000ms.
        assertEquals(calculateBackoff(3, 60), d.delayMs)
    }

    @Test
    fun decideRetry_noneDoesNotOverrideStatus() {
        val d = decideRetry(true, false, "none", 0, 5, 60)
        assertNull(d.statusOverride)
    }
}
