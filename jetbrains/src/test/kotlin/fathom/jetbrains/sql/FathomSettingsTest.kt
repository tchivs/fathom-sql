package fathom.jetbrains.sql

import kotlin.test.Test
import kotlin.test.assertEquals
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
    fun onlyReleasedDialectsAndProfilesAreAccepted() {
        assertEquals(listOf("doris", "flink"), FathomSettings.ALLOWED_DIALECTS)
        assertEquals(listOf("2.1", "3.x", "4.x"), FathomSettings.ALLOWED_PROFILES)
        FathomSettings.ALLOWED_DIALECTS.forEach { assertEquals(it, FathomSettings.normalizeDialect(it)) }
        FathomSettings.ALLOWED_PROFILES.forEach { assertEquals(it, FathomSettings.normalizeProfile(it)) }
        assertNull(FathomSettings.normalizeDialect("generic"))
        assertNull(FathomSettings.normalizeProfile("mysql"))
        assertNull(FathomSettings.normalizeDialect(""))
        assertNull(FathomSettings.normalizeProfile(""))
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
        assertTrue(FathomLanguageServerFactory.initializationOptions("flink", "3.x").containsKey("dialect"))
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
