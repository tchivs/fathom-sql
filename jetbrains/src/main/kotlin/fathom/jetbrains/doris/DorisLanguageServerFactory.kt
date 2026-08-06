package fathom.jetbrains.doris

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.redhat.devtools.lsp4ij.LanguageServerFactory
import com.redhat.devtools.lsp4ij.server.OSProcessStreamConnectionProvider
import com.redhat.devtools.lsp4ij.server.StreamConnectionProvider

class DorisLanguageServerFactory : LanguageServerFactory {
    override fun createConnectionProvider(project: Project): StreamConnectionProvider {
        val configuration = DorisSettings.getInstance().snapshot()
        val executablePath = resolveExecutable(configuration)
        return DorisConnectionProvider(configuration, executablePath)
    }

    private class DorisConnectionProvider(
        private val configuration: DorisSettings.Configuration,
        executablePath: String,
    ) : OSProcessStreamConnectionProvider(GeneralCommandLine(executablePath)) {
        override fun getInitializationOptions(rootUri: VirtualFile): Any =
            initializationOptions(configuration.profile)
    }

    companion object {
        private val LOG = Logger.getInstance(DorisLanguageServerFactory::class.java)

        internal fun resolveExecutable(
            configuration: DorisSettings.Configuration,
            downloader: DorisNativeDownloader = DorisNativeDownloader(),
        ): String {
            if (!configuration.useGitHubReleases) return configuration.executablePath
            return try {
                downloader.resolve().toString()
            } catch (failure: Exception) {
                LOG.warn("Unable to download managed doris-lsp; using configured executable", failure)
                configuration.executablePath
            }
        }

        fun initializationOptions(profile: String): Map<String, String> = mapOf("profile" to profile)
    }
}

