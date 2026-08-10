package fathom.jetbrains.sql

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Gradle-level LSP launch smoke (D-08): proves the IntelliJ host sends a flink
 * (dialect, profile) selection over the LSP wire via
 * [FathomLanguageServerFactory.initializationOptions]. The factory's
 * `getInitializationOptions` builds this map from `FathomSettings.Configuration`
 * (dialect/profile), so a flink configuration must round-trip through the same
 * static function the connection provider calls — no network, no IDE runtime
 * (offline-first, PARITY-03).
 */
class FathomLanguageServerFactoryTest {
    @Test
    fun initializationOptionsCarryAFlinkSelectionOverTheLspWire() {
        val options = FathomLanguageServerFactory.initializationOptions("flink", "flink-2.3.0")
        assertEquals(
            mapOf("dialect" to "flink", "profile" to "flink-2.3.0"),
            options,
            "a flink selection must reach the LSP as {dialect: flink, profile: flink-2.3.0}",
        )
    }

    @Test
    fun flinkSelectionFlowsFromSettingsThroughTheFactory() {
        // The settings snapshot is the only source for the factory's
        // initializationOptions; normalizeDialect/normalizeProfile are the same
        // validators the settings UI and loadState use (D-05 per-dialect pairs).
        val dialect = FathomSettings.normalizeDialect("flink")
        val profile = FathomSettings.normalizeProfile("flink", "flink-2.3.0")
        assertEquals("flink", dialect)
        assertEquals("flink-2.3.0", profile)
        assertEquals(
            mapOf("dialect" to "flink", "profile" to "flink-2.3.0"),
            FathomLanguageServerFactory.initializationOptions(dialect!!, profile!!),
            "a settings-accepted flink pair must carry through initializationOptions",
        )
    }

    @Test
    fun initializationOptionsCarryTheDorisPairAsBaseline() {
        assertEquals(
            mapOf("dialect" to "doris", "profile" to "4.x"),
            FathomLanguageServerFactory.initializationOptions("doris", "4.x"),
            "the doris baseline pair must remain byte-identical",
        )
    }
}
