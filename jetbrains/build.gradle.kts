plugins {
    id("java")
    id("org.jetbrains.kotlin.jvm") version "2.2.0"
    id("org.jetbrains.intellij.platform") version "2.9.0"
}

group = "fathom.jetbrains"
version = "0.1.0"

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

kotlin {
    jvmToolchain(21)
}

intellijPlatform {
    pluginConfiguration {
        ideaVersion {
            sinceBuild = "252"
            untilBuild = "253.*"
        }
        changeNotes = "Initial Doris SQL LSP4IJ integration."
    }
}

dependencies {
    intellijPlatform {
        intellijIdeaCommunity("2025.2")
        plugin("com.redhat.devtools.lsp4ij", "0.20.1")
    }
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
