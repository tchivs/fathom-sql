package fathom.jetbrains.doris

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.redhat.devtools.lsp4ij.LanguageServerFactory
import com.redhat.devtools.lsp4ij.server.OSProcessStreamConnectionProvider
import com.redhat.devtools.lsp4ij.server.StreamConnectionProvider

class DorisLanguageServerFactory : LanguageServerFactory {
    override fun createConnectionProvider(project: Project): StreamConnectionProvider {
        val configuration = DorisSettings.getInstance().snapshot()
        return DorisConnectionProvider(configuration)
    }

    private class DorisConnectionProvider(
        private val configuration: DorisSettings.Configuration,
    ) : OSProcessStreamConnectionProvider(GeneralCommandLine(configuration.executablePath)) {
        override fun getInitializationOptions(rootUri: VirtualFile): Any =
            initializationOptions(configuration.profile)
    }

    companion object {
        fun initializationOptions(profile: String): Map<String, String> = mapOf("profile" to profile)
    }
}
