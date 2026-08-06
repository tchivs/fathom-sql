package fathom.jetbrains.sql

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.redhat.devtools.lsp4ij.LanguageServerFactory
import com.redhat.devtools.lsp4ij.server.OSProcessStreamConnectionProvider
import com.redhat.devtools.lsp4ij.server.StreamConnectionProvider

class FathomLanguageServerFactory : LanguageServerFactory {
    override fun createConnectionProvider(project: Project): StreamConnectionProvider {
        val configuration = FathomSettings.getInstance().snapshot()
        val executablePath = resolveExecutable(configuration)
        return FathomConnectionProvider(configuration, executablePath)
    }

    private class FathomConnectionProvider(
        private val configuration: FathomSettings.Configuration,
        executablePath: String,
    ) : OSProcessStreamConnectionProvider(GeneralCommandLine(executablePath)) {
        override fun getInitializationOptions(rootUri: VirtualFile): Any =
            initializationOptions(configuration.dialect, configuration.profile)
    }

    companion object {
        private val LOG = Logger.getInstance(FathomLanguageServerFactory::class.java)

        internal fun resolveExecutable(
            configuration: FathomSettings.Configuration,
            downloader: FathomNativeDownloader = FathomNativeDownloader(),
        ): String {
            if (!configuration.useGitHubReleases) return configuration.executablePath
            return try {
                downloader.resolve().toString()
            } catch (failure: Exception) {
                LOG.warn("Unable to download managed fathom-lsp; using configured executable", failure)
                configuration.executablePath
            }
        }

        fun initializationOptions(dialect: String, profile: String): Map<String, String> =
            mapOf("dialect" to dialect, "profile" to profile)
    }
}
