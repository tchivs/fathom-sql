package fathom.jetbrains.sql

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FathomSettingsTest {
    @Test
    fun defaultsUseManagedGitHubReleaseServerAndNoImplicitSelection() {
        val defaults = FathomSettings.State()
        assertEquals("fathom-lsp", defaults.executablePath)
        // D-02: no default dialect/profile — an empty selection is an explicit
        // configuration error, never a silent fallback.
        assertEquals("", defaults.dialect)
        assertEquals("", defaults.profile)
        assertTrue(defaults.useGitHubReleases)
    }

    @Test
    fun onlyReleasedDialectsAndPerDialectProfilesAreAccepted() {
        assertEquals(listOf("doris", "flink"), FathomSettings.ALLOWED_DIALECTS)
        // D-05: per-dialect (dialect, profile) pairs — flink values only under flink.
        assertEquals(
            mapOf(
                "doris" to listOf("2.1", "3.x", "4.x"),
                "flink" to listOf("flink-2.3.0", "flink-2.1.3", "flink-1.20.5"),
            ),
            FathomSettings.PROFILES_BY_DIALECT,
        )
        FathomSettings.ALLOWED_DIALECTS.forEach { assertEquals(it, FathomSettings.normalizeDialect(it)) }
        FathomSettings.PROFILES_BY_DIALECT.getValue("doris").forEach {
            assertEquals(it, FathomSettings.normalizeProfile("doris", it))
        }
        FathomSettings.PROFILES_BY_DIALECT.getValue("flink").forEach {
            assertEquals(it, FathomSettings.normalizeProfile("flink", it))
        }
        assertNull(FathomSettings.normalizeDialect("generic"))
        assertNull(FathomSettings.normalizeDialect(""))
        // Cross-dialect and unknown profiles are rejected (D-05, D-02).
        assertNull(FathomSettings.normalizeProfile("doris", "mysql"))
        assertNull(FathomSettings.normalizeProfile("flink", "2.1"))
        assertNull(FathomSettings.normalizeProfile("doris", "flink-2.3.0"))
        assertNull(FathomSettings.normalizeProfile("", "2.1"))
        assertNull(FathomSettings.normalizeProfile("flink", ""))
    }

    @Test
    fun executablePathMustContainACommand() {
        assertEquals("/opt/bin/fathom-lsp", FathomSettings.normalizeExecutablePath("  /opt/bin/fathom-lsp "))
        assertNull(FathomSettings.normalizeExecutablePath("  "))
        assertNull(FathomSettings.normalizeExecutablePath(null))
    }

    @Test
    fun initializationOptionsUseTheNativeServerDialectAndProfileFields() {
        assertEquals(mapOf("dialect" to "doris", "profile" to "2.1"), FathomLanguageServerFactory.initializationOptions("doris", "2.1"))
        assertTrue(FathomLanguageServerFactory.initializationOptions("flink", "flink-2.3.0").containsKey("dialect"))
    }

    @Test
    fun updateRejectsCrossDialectProfilePairs() {
        val settings = FathomSettings()
        assertFailsWith<IllegalArgumentException> { settings.update("fathom-lsp", "flink", "2.1") }
        assertFailsWith<IllegalArgumentException> { settings.update("fathom-lsp", "doris", "flink-2.3.0") }
        assertFailsWith<IllegalArgumentException> { settings.update("fathom-lsp", "flink", "4.x") }
        // The settings state is untouched by a rejected update (D-05 no coercion).
        assertEquals("", settings.snapshot().dialect)
        assertEquals("", settings.snapshot().profile)
    }

    @Test
    fun invalidPersistedValuesKeepTheManagedServerDefault() {
        val settings = FathomSettings()
        settings.loadState(FathomSettings.State(" ", "generic", "mysql"))
        assertEquals(FathomSettings.DEFAULT_EXECUTABLE, settings.snapshot().executablePath)
        assertEquals("", settings.snapshot().dialect)
        assertEquals("", settings.snapshot().profile)
        assertTrue(settings.snapshot().useGitHubReleases)
    }

    @Test
    fun settingsUpdateAffectsOnlyTheNextConfigurationSnapshot() {
        val settings = FathomSettings()
        val first = settings.snapshot()
        settings.update("custom-fathom-lsp", "doris", "2.1", useGitHubReleases = false)
        val second = settings.snapshot()
        assertEquals("fathom-lsp", first.executablePath)
        assertEquals("", first.dialect)
        assertEquals("", first.profile)
        assertEquals("custom-fathom-lsp", second.executablePath)
        assertEquals("doris", second.dialect)
        assertEquals("2.1", second.profile)
        assertTrue(!second.useGitHubReleases)
    }
}
