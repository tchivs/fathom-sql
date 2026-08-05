package fathom.jetbrains.doris

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DorisSettingsTest {
    @Test
    fun defaultsUseLocalDorisServerAndLatestProfile() {
        val defaults = DorisSettings.State()
        assertEquals("doris-lsp", defaults.executablePath)
        assertEquals("4.x", defaults.profile)
    }

    @Test
    fun onlyReleasedProfilesAreAccepted() {
        assertEquals(listOf("2.1", "3.x", "4.x"), DorisSettings.ALLOWED_PROFILES)
        DorisSettings.ALLOWED_PROFILES.forEach { assertEquals(it, DorisSettings.normalizeProfile(it)) }
        assertNull(DorisSettings.normalizeProfile("generic"))
        assertNull(DorisSettings.normalizeProfile("mysql"))
        assertNull(DorisSettings.normalizeProfile(""))
    }

    @Test
    fun executablePathMustContainACommand() {
        assertEquals("/opt/bin/doris-lsp", DorisSettings.normalizeExecutablePath("  /opt/bin/doris-lsp "))
        assertNull(DorisSettings.normalizeExecutablePath("  "))
        assertNull(DorisSettings.normalizeExecutablePath(null))
    }

    @Test
    fun initializationOptionsUseTheNativeServerProfileField() {
        assertEquals(mapOf("profile" to "2.1"), DorisLanguageServerFactory.initializationOptions("2.1"))
        assertTrue(DorisLanguageServerFactory.initializationOptions("3.x").containsKey("profile"))
    }

    @Test
    fun invalidPersistedValuesNeverSelectGenericProfile() {
        val settings = DorisSettings()
        settings.loadState(DorisSettings.State(" ", "generic"))
        assertEquals(DorisSettings.DEFAULT_EXECUTABLE, settings.snapshot().executablePath)
        assertEquals(DorisSettings.DEFAULT_PROFILE, settings.snapshot().profile)
    }

    @Test
    fun settingsUpdateAffectsOnlyTheNextConfigurationSnapshot() {
        val settings = DorisSettings()
        val first = settings.snapshot()
        settings.update("custom-doris-lsp", "2.1")
        val second = settings.snapshot()
        assertEquals("doris-lsp", first.executablePath)
        assertEquals("4.x", first.profile)
        assertEquals("custom-doris-lsp", second.executablePath)
        assertEquals("2.1", second.profile)
    }
}
