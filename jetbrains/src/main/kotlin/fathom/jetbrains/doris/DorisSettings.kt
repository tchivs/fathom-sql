package fathom.jetbrains.doris

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage
import com.intellij.openapi.components.PersistentStateComponent

@Service(Service.Level.APP)
@State(name = "DorisSettings", storages = [Storage("doris.xml")])
class DorisSettings : PersistentStateComponent<DorisSettings.State> {
    data class State(
        var executablePath: String = DEFAULT_EXECUTABLE,
        var profile: String = DEFAULT_PROFILE,
        var useGitHubReleases: Boolean = DEFAULT_USE_GITHUB_RELEASES,
    )

    private var state = State()

    override fun getState(): State = state.copy()

    override fun loadState(loadedState: State) {
        state = State(
            executablePath = normalizeExecutablePath(loadedState.executablePath) ?: DEFAULT_EXECUTABLE,
            profile = normalizeProfile(loadedState.profile) ?: DEFAULT_PROFILE,
            useGitHubReleases = loadedState.useGitHubReleases,
        )
    }

    fun snapshot(): Configuration =
        Configuration(state.executablePath, state.profile, state.useGitHubReleases)

    fun update(executablePath: String, profile: String, useGitHubReleases: Boolean = state.useGitHubReleases) {
        val normalizedPath = normalizeExecutablePath(executablePath)
            ?: throw IllegalArgumentException("doris-lsp executable path must not be empty")
        val normalizedProfile = normalizeProfile(profile)
            ?: throw IllegalArgumentException("Doris profile must be one of: ${ALLOWED_PROFILES.joinToString()}")
        state = State(normalizedPath, normalizedProfile, useGitHubReleases)
    }

    data class Configuration(
        val executablePath: String,
        val profile: String,
        val useGitHubReleases: Boolean,
    )

    companion object {
        const val DEFAULT_EXECUTABLE = "doris-lsp"
        const val DEFAULT_PROFILE = "4.x"
        const val DEFAULT_USE_GITHUB_RELEASES = true
        val ALLOWED_PROFILES: List<String> = listOf("2.1", "3.x", "4.x")

        fun getInstance(): DorisSettings =
            ApplicationManager.getApplication().getService(DorisSettings::class.java)

        fun normalizeExecutablePath(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

        fun normalizeProfile(value: String?): String? = value?.trim()?.takeIf { it in ALLOWED_PROFILES }
    }
}
