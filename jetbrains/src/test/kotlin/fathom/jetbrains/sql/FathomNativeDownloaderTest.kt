package fathom.jetbrains.sql

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class FathomNativeDownloaderTest {
    @Test
    fun detectsTheFourPublishedPlatformKeys() {
        assertEquals(
            FathomNativePlatform.LINUX_X86_64,
            FathomNativePlatform.detect("Linux", "amd64"),
        )
        assertEquals(
            FathomNativePlatform.MACOS_X86_64,
            FathomNativePlatform.detect("Mac OS X", "x86_64"),
        )
        assertEquals(
            FathomNativePlatform.MACOS_AARCH64,
            FathomNativePlatform.detect("Darwin", "arm64"),
        )
        assertEquals(
            FathomNativePlatform.WINDOWS_X86_64,
            FathomNativePlatform.detect("Windows 11", "amd64"),
        )
        assertFailsWith<IllegalStateException> {
            FathomNativePlatform.detect("Linux", "aarch64")
        }
    }

    @Test
    fun downloadsVerifiesAndThenReusesTheCachedBinary() {
        val binary = "fathom-lsp-test-binary".toByteArray(StandardCharsets.UTF_8)
        val sha256 = sha256(binary)
        val tag = "v0.1.0"
        val repository = FathomNativeDownloader.DEFAULT_REPOSITORY
        val apiUrl = "https://api.github.com/repos/$repository/releases/latest"
        val manifestUrl = "https://github.com/$repository/releases/download/$tag/${FathomNativeDownloader.MANIFEST_ASSET_NAME}"
        val binaryUrl = "https://github.com/$repository/releases/download/$tag/fathom-lsp-linux-x86_64"
        val transport = FakeTransport(
            mapOf(
                apiUrl to """
                    {"tag_name":"$tag","assets":[
                      {"name":"${FathomNativeDownloader.MANIFEST_ASSET_NAME}","browser_download_url":"$manifestUrl"},
                      {"name":"fathom-lsp-linux-x86_64","browser_download_url":"$binaryUrl"}
                    ]}
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                manifestUrl to """
                    {"schemaVersion":1,"tag":"$tag","assets":{
                      "linux-x86_64":{"name":"fathom-lsp-linux-x86_64","sha256":"$sha256"}
                    }}
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                binaryUrl to binary,
            ),
        )
        val cache = Files.createTempDirectory("fathom-native-downloader")
        val downloader = FathomNativeDownloader(
            cacheDirectory = cache,
            platform = FathomNativePlatform.LINUX_X86_64,
            transport = transport,
            cacheTtlMillis = Long.MAX_VALUE,
        )

        val firstPath = downloader.resolve()
        assertEquals(binary.toList(), Files.readAllBytes(firstPath).toList())
        assertEquals(listOf(apiUrl, manifestUrl, binaryUrl), transport.requests)

        transport.requests.clear()
        val secondPath = downloader.resolve()
        assertEquals(firstPath, secondPath)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun rejectsAReleaseWhoseBinaryHashDoesNotMatchTheManifest() {
        val tag = "v0.1.0"
        val repository = FathomNativeDownloader.DEFAULT_REPOSITORY
        val apiUrl = "https://api.github.com/repos/$repository/releases/latest"
        val manifestUrl = "https://github.com/$repository/releases/download/$tag/${FathomNativeDownloader.MANIFEST_ASSET_NAME}"
        val binaryUrl = "https://github.com/$repository/releases/download/$tag/fathom-lsp-linux-x86_64"
        val transport = FakeTransport(
            mapOf(
                apiUrl to """
                    {"tag_name":"$tag","assets":[
                      {"name":"${FathomNativeDownloader.MANIFEST_ASSET_NAME}","browser_download_url":"$manifestUrl"},
                      {"name":"fathom-lsp-linux-x86_64","browser_download_url":"$binaryUrl"}
                    ]}
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                manifestUrl to """
                    {"schemaVersion":1,"tag":"$tag","assets":{
                      "linux-x86_64":{"name":"fathom-lsp-linux-x86_64","sha256":"${"0".repeat(64)}"}
                    }}
                """.trimIndent().toByteArray(StandardCharsets.UTF_8),
                binaryUrl to "not-the-expected-binary".toByteArray(StandardCharsets.UTF_8),
            ),
        )
        val downloader = FathomNativeDownloader(
            cacheDirectory = Files.createTempDirectory("fathom-native-hash-test"),
            platform = FathomNativePlatform.LINUX_X86_64,
            transport = transport,
            cacheTtlMillis = Long.MAX_VALUE,
        )

        assertFailsWith<IllegalArgumentException> { downloader.resolve() }
    }

    @Test
    fun managedResolutionFallsBackToTheConfiguredCommandWhenDownloadFails() {
        val configuration = FathomSettings.Configuration("local-fathom-lsp", "doris", "2.1", true)
        val failingDownloader = FathomNativeDownloader(
            cacheDirectory = Files.createTempDirectory("fathom-native-fallback"),
            platform = FathomNativePlatform.LINUX_X86_64,
            transport = NativeHttpTransport { error("network unavailable") },
        )

        assertEquals(
            "local-fathom-lsp",
            FathomLanguageServerFactory.resolveExecutable(configuration, failingDownloader),
        )
    }

    private class FakeTransport(
        private val responses: Map<String, ByteArray>,
    ) : NativeHttpTransport {
        val requests = mutableListOf<String>()

        override fun get(url: String): ByteArray {
            requests += url
            return responses[url] ?: error("Unexpected URL: $url")
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
