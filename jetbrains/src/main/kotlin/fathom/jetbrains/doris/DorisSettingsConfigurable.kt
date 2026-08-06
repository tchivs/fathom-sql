package fathom.jetbrains.doris

import com.intellij.openapi.options.Configurable
import com.intellij.openapi.options.ConfigurationException
import com.intellij.openapi.ui.ComboBox
import com.intellij.ui.components.JBCheckBox
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBTextField
import com.intellij.util.ui.FormBuilder
import javax.swing.JComponent
import javax.swing.JPanel

class DorisSettingsConfigurable : Configurable {
    private val executableField = JBTextField()
    private val profileCombo = ComboBox(DorisSettings.ALLOWED_PROFILES.toTypedArray())
    private val useGitHubReleases = JBCheckBox("Download managed doris-lsp binaries from GitHub Releases")
    private val panel: JPanel = FormBuilder.createFormBuilder()
        .addLabeledComponent(JBLabel("doris-lsp executable:"), executableField, 1, false)
        .addLabeledComponent(JBLabel("Doris profile:"), profileCombo, 1, false)
        .addComponent(useGitHubReleases)
        .addComponentFillVertically(JPanel(), 0)
        .panel

    override fun getDisplayName(): String = "Doris SQL"

    override fun createComponent(): JComponent = panel

    override fun isModified(): Boolean {
        val current = DorisSettings.getInstance().snapshot()
        return executableField.text != current.executablePath ||
            profileCombo.selectedItem != current.profile ||
            useGitHubReleases.isSelected != current.useGitHubReleases
    }

    @Throws(ConfigurationException::class)
    override fun apply() {
        val executable = DorisSettings.normalizeExecutablePath(executableField.text)
            ?: throw ConfigurationException("Executable path must not be empty")
        val profile = DorisSettings.normalizeProfile(profileCombo.selectedItem as? String)
            ?: throw ConfigurationException("Profile must be one of: ${DorisSettings.ALLOWED_PROFILES.joinToString()}")
        DorisSettings.getInstance().update(executable, profile, useGitHubReleases.isSelected)
    }

    override fun reset() {
        val current = DorisSettings.getInstance().snapshot()
        executableField.text = current.executablePath
        profileCombo.selectedItem = current.profile
        useGitHubReleases.isSelected = current.useGitHubReleases
    }

    override fun disposeUIResources() {
        executableField.text = ""
    }
}
