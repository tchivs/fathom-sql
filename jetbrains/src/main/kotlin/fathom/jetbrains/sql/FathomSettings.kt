package fathom.jetbrains.sql

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.PersistentStateComponent
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage

@Service(Service.Level.APP)
@State(name = "FathomSettings", storages = [Storage("fathom.xml")])
class FathomSettings : PersistentStateComponent<FathomSettings.State> {
    data class State(
        var executablePath: String = DEFAULT_EXECUTABLE,
        // D-02: no default dialect and no default profile — an empty selection
        // is an explicit configuration error surfaced by the LSP server, never
        // an implicit fallback.
        var dialect: String = "",
        var profile: String = "",
        var useGitHubReleases: Boolean = DEFAULT_USE_GITHUB_RELEASES,
    )

    private var state = State()

    override fun getState(): State = state.copy()

    override fun loadState(loadedState: State) {
        state = State(
            executablePath = normalizeExecutablePath(loadedState.executablePath) ?: DEFAULT_EXECUTABLE,
            dialect = normalizeDialect(loadedState.dialect) ?: "",
            profile = normalizeProfile(loadedState.profile) ?: "",
            useGitHubReleases = loadedState.useGitHubReleases,
        )
    }

    fun snapshot(): Configuration =
        Configuration(state.executablePath, state.dialect, state.profile, state.useGitHubReleases)

    fun update(executablePath: String, dialect: String, profile: String, useGitHubReleases: Boolean = state.useGitHubReleases) {
        val normalizedPath = normalizeExecutablePath(executablePath)
            ?: throw IllegalArgumentException("fathom-lsp executable path must not be empty")
        val normalizedDialect = normalizeDialect(dialect)
            ?: throw IllegalArgumentException("Dialect must be one of: ${ALLOWED_DIALECTS.joinToString()}")
        val normalizedProfile = normalizeProfile(profile)
            ?: throw IllegalArgumentException("Profile must be one of: ${ALLOWED_PROFILES.joinToString()}")
        state = State(normalizedPath, normalizedDialect, normalizedProfile, useGitHubReleases)
    }

    data class Configuration(
        val executablePath: String,
        val dialect: String,
        val profile: String,
        val useGitHubReleases: Boolean,
    )

    companion object {
        const val DEFAULT_EXECUTABLE = "fathom-lsp"
        const val DEFAULT_USE_GITHUB_RELEASES = true
        val ALLOWED_DIALECTS: List<String> = listOf("doris", "flink")
        val ALLOWED_PROFILES: List<String> = listOf("2.1", "3.x", "4.x")

        fun getInstance(): FathomSettings =
            ApplicationManager.getApplication().getService(FathomSettings::class.java)

        fun normalizeExecutablePath(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

        fun normalizeDialect(value: String?): String? = value?.trim()?.takeIf { it in ALLOWED_DIALECTS }

        fun normalizeProfile(value: String?): String? = value?.trim()?.takeIf { it in ALLOWED_PROFILES }
    }
}
