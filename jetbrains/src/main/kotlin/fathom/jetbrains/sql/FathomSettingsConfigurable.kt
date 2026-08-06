package fathom.jetbrains.sql

import com.intellij.openapi.options.Configurable
import com.intellij.openapi.options.ConfigurationException
import com.intellij.openapi.ui.ComboBox
import com.intellij.ui.components.JBCheckBox
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBTextField
import com.intellij.util.ui.FormBuilder
import javax.swing.JComponent
import javax.swing.JPanel

class FathomSettingsConfigurable : Configurable {
    private val executableField = JBTextField()
    private val dialectCombo = ComboBox(FathomSettings.ALLOWED_DIALECTS.toTypedArray())
    private val profileCombo = ComboBox(FathomSettings.ALLOWED_PROFILES.toTypedArray())
    private val useGitHubReleases = JBCheckBox("Download managed fathom-lsp binaries from GitHub Releases")
    private val panel: JPanel = FormBuilder.createFormBuilder()
        .addLabeledComponent(JBLabel("fathom-lsp executable:"), executableField, 1, false)
        .addLabeledComponent(JBLabel("Dialect:"), dialectCombo, 1, false)
        .addLabeledComponent(JBLabel("Profile:"), profileCombo, 1, false)
        .addComponent(useGitHubReleases)
        .addComponentFillVertically(JPanel(), 0)
        .panel

    override fun getDisplayName(): String = "Fathom SQL"

    override fun createComponent(): JComponent = panel

    override fun isModified(): Boolean {
        val current = FathomSettings.getInstance().snapshot()
        return executableField.text != current.executablePath ||
            dialectCombo.selectedItem != current.dialect ||
            profileCombo.selectedItem != current.profile ||
            useGitHubReleases.isSelected != current.useGitHubReleases
    }

    @Throws(ConfigurationException::class)
    override fun apply() {
        val executable = FathomSettings.normalizeExecutablePath(executableField.text)
            ?: throw ConfigurationException("Executable path must not be empty")
        val dialect = FathomSettings.normalizeDialect(dialectCombo.selectedItem as? String)
            ?: throw ConfigurationException("Dialect must be one of: ${FathomSettings.ALLOWED_DIALECTS.joinToString()}")
        val profile = FathomSettings.normalizeProfile(profileCombo.selectedItem as? String)
            ?: throw ConfigurationException("Profile must be one of: ${FathomSettings.ALLOWED_PROFILES.joinToString()}")
        FathomSettings.getInstance().update(executable, dialect, profile, useGitHubReleases.isSelected)
    }

    override fun reset() {
        val current = FathomSettings.getInstance().snapshot()
        executableField.text = current.executablePath
        dialectCombo.selectedItem = current.dialect
        profileCombo.selectedItem = current.profile
        useGitHubReleases.isSelected = current.useGitHubReleases
    }

    override fun disposeUIResources() {
        executableField.text = ""
    }
}
