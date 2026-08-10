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
        val dialect = normalizeDialect(loadedState.dialect) ?: ""
        state = State(
            executablePath = normalizeExecutablePath(loadedState.executablePath) ?: DEFAULT_EXECUTABLE,
            dialect = dialect,
            profile = normalizeProfile(dialect, loadedState.profile) ?: "",
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
        val normalizedProfile = normalizeProfile(normalizedDialect, profile)
            ?: throw IllegalArgumentException("Profile must be one of: ${PROFILES_BY_DIALECT[normalizedDialect].orEmpty().joinToString()}")
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
        // D-05: per-dialect (dialect, profile) pairs — the flat ALLOWED_PROFILES
        // list is replaced by a per-dialect map (doris -> 2.1/3.x/4.x; flink ->
        // flink-2.3.0/2.1.3/1.20.5). Static constants only: no dynamic pull, no
        // shared cross-host JSON (offline-first, PARITY-03).
        val PROFILES_BY_DIALECT: Map<String, List<String>> = mapOf(
            "doris" to listOf("2.1", "3.x", "4.x"),
            "flink" to listOf("flink-2.3.0", "flink-2.1.3", "flink-1.20.5"),
        )

        fun getInstance(): FathomSettings =
            ApplicationManager.getApplication().getService(FathomSettings::class.java)

        fun normalizeExecutablePath(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

        fun normalizeDialect(value: String?): String? = value?.trim()?.takeIf { it in ALLOWED_DIALECTS }

        // D-05: a profile is valid only when it belongs to the selected
        // dialect's list — flink + '2.1' -> null, flink + 'flink-2.3.0' ->
        // 'flink-2.3.0'. No cross-dialect value and no coerced default (D-02).
        fun normalizeProfile(dialect: String, value: String?): String? =
            value?.trim()?.takeIf { PROFILES_BY_DIALECT[dialect]?.contains(it) == true }
    }
}
