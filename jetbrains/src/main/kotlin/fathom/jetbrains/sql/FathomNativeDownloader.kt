package fathom.jetbrains.sql

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.charset.StandardCharsets
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.util.Locale

internal enum class FathomNativePlatform(
    val key: String,
    val assetName: String,
) {
    LINUX_X86_64("linux-x86_64", "fathom-lsp-linux-x86_64"),
    MACOS_X86_64("macos-x86_64", "fathom-lsp-macos-x86_64"),
    MACOS_AARCH64("macos-aarch64", "fathom-lsp-macos-aarch64"),
    WINDOWS_X86_64("windows-x86_64", "fathom-lsp-windows-x86_64.exe"),
    ;

    companion object {
        fun detect(
            osName: String = System.getProperty("os.name"),
            architecture: String = System.getProperty("os.arch"),
        ): FathomNativePlatform {
            val os = osName.lowercase(Locale.ROOT)
            val arch = architecture.lowercase(Locale.ROOT)
            val isX86_64 = arch == "amd64" || arch == "x86_64" || arch == "x86-64"
            val isAarch64 = arch == "aarch64" || arch == "arm64"
            return when {
                os.contains("windows") && isX86_64 -> WINDOWS_X86_64
                os.contains("linux") && isX86_64 -> LINUX_X86_64
                (os.contains("mac") || os.contains("darwin")) && isX86_64 -> MACOS_X86_64
                (os.contains("mac") || os.contains("darwin")) && isAarch64 -> MACOS_AARCH64
                else -> throw IllegalStateException("Unsupported fathom-lsp platform: $osName/$architecture")
            }
        }
    }
}

internal fun interface NativeHttpTransport {
    @Throws(IOException::class)
    fun get(url: String): ByteArray
}

internal class FathomNativeDownloader(
    private val cacheDirectory: Path = defaultCacheDirectory(),
    private val platform: FathomNativePlatform = FathomNativePlatform.detect(),
    private val transport: NativeHttpTransport = UrlConnectionTransport(),
    private val clockMillis: () -> Long = { System.currentTimeMillis() },
    private val cacheTtlMillis: Long = CACHE_TTL_MILLIS,
    private val repository: String = DEFAULT_REPOSITORY,
) {
    fun resolve(): Path {
        val cached = readCached()
        if (cached != null && isFresh(cached.metadataPath)) {
            return cached.binaryPath
        }
        return try {
            downloadLatest()
        } catch (failure: Exception) {
            cached?.binaryPath ?: throw failure
        }
    }

    private fun downloadLatest(): Path {
        val release = parseRelease(transport.get(releaseApiUrl()))
        val manifestAsset = release.assets[MANIFEST_ASSET_NAME]
            ?: error("GitHub release ${release.tag} has no $MANIFEST_ASSET_NAME asset")
        val manifestUrl = allowedAssetUrl(manifestAsset)
        val manifest = parseManifest(transport.get(manifestUrl), release.tag)
        val descriptor = manifest.assets[platform.key]
            ?: error("Native manifest has no ${platform.key} asset")
        require(descriptor.name == platform.assetName) {
            "Native manifest asset name mismatch for ${platform.key}"
        }
        require(SHA256_PATTERN.matches(descriptor.sha256)) {
            "Native manifest contains an invalid SHA-256 for ${platform.key}"
        }

        val releaseBinary = release.assets[descriptor.name]
            ?: error("GitHub release ${release.tag} has no ${descriptor.name} asset")
        val binaryPath = cacheDirectory.resolve(safeTag(release.tag)).resolve(descriptor.name)
        Files.createDirectories(binaryPath.parent)
        if (!isValidFile(binaryPath, descriptor.sha256)) {
            val bytes = transport.get(allowedAssetUrl(releaseBinary))
            require(sha256(bytes) == descriptor.sha256.lowercase(Locale.ROOT)) {
                "SHA-256 verification failed for ${descriptor.name}"
            }
            val temporaryPath = binaryPath.resolveSibling(".${descriptor.name}.download")
            Files.write(
                temporaryPath,
                bytes,
                StandardOpenOption.CREATE,
                StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE,
            )
            moveAtomically(temporaryPath, binaryPath)
            binaryPath.toFile().setExecutable(true, false)
        }

        val metadata = CacheMetadata(
            tag = release.tag,
            assetName = descriptor.name,
            sha256 = descriptor.sha256.lowercase(Locale.ROOT),
            relativePath = cacheDirectory.relativize(binaryPath).toString(),
        )
        writeMetadata(metadata)
        return binaryPath
    }

    private fun readCached(): CachedBinary? {
        val metadataPath = cacheDirectory.resolve(METADATA_FILE_NAME)
        return try {
            if (!Files.isRegularFile(metadataPath)) return null
            val root = parseObject(Files.readAllBytes(metadataPath), "cache metadata")
            val metadata = CacheMetadata(
                tag = requiredString(root, "tag"),
                assetName = requiredString(root, "assetName"),
                sha256 = requiredString(root, "sha256").lowercase(Locale.ROOT),
                relativePath = requiredString(root, "relativePath"),
            )
            if (metadata.assetName != platform.assetName || !SHA256_PATTERN.matches(metadata.sha256)) {
                return null
            }
            val binaryPath = cacheDirectory.resolve(metadata.relativePath).normalize()
            if (!binaryPath.startsWith(cacheDirectory.normalize())) return null
            if (!isValidFile(binaryPath, metadata.sha256)) return null
            CachedBinary(metadataPath, binaryPath)
        } catch (_: Exception) {
            null
        }
    }

    private fun isFresh(metadataPath: Path): Boolean {
        if (cacheTtlMillis < 0) return false
        val age = clockMillis() - Files.getLastModifiedTime(metadataPath).toMillis()
        return age in 0..cacheTtlMillis
    }

    private fun isValidFile(path: Path, expectedSha256: String): Boolean =
        Files.isRegularFile(path) && sha256(path) == expectedSha256.lowercase(Locale.ROOT)

    private fun writeMetadata(metadata: CacheMetadata) {
        Files.createDirectories(cacheDirectory)
        val root = JsonObject().apply {
            addProperty("tag", metadata.tag)
            addProperty("assetName", metadata.assetName)
            addProperty("sha256", metadata.sha256)
            addProperty("relativePath", metadata.relativePath)
        }
        val metadataPath = cacheDirectory.resolve(METADATA_FILE_NAME)
        val temporaryPath = metadataPath.resolveSibling(".$METADATA_FILE_NAME.tmp")
        Files.writeString(
            temporaryPath,
            root.toString(),
            StandardCharsets.UTF_8,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING,
            StandardOpenOption.WRITE,
        )
        moveAtomically(temporaryPath, metadataPath)
    }

    private fun parseRelease(bytes: ByteArray): Release {
        val root = parseObject(bytes, "GitHub release response")
        val tag = requiredString(root, "tag_name")
        val assets = parseAssets(root, "assets")
        return Release(tag, assets)
    }

    private fun parseManifest(bytes: ByteArray, releaseTag: String): Manifest {
        val root = parseObject(bytes, "Native release manifest")
        require(root.get("schemaVersion")?.asInt == MANIFEST_SCHEMA_VERSION) {
            "Unsupported native manifest schema"
        }
        require(requiredString(root, "tag") == releaseTag) {
            "Native manifest tag does not match GitHub release tag"
        }
        val assetsObject = root.getAsJsonObject("assets")
            ?: error("Native release manifest has no assets object")
        val assets = buildMap {
            for ((key, element) in assetsObject.entrySet()) {
                require(element.isJsonObject) { "Native manifest asset $key is not an object" }
                val descriptor = element.asJsonObject
                put(
                    key,
                    ManifestAsset(
                        name = requiredString(descriptor, "name"),
                        sha256 = requiredString(descriptor, "sha256"),
                    ),
                )
            }
        }
        return Manifest(requiredString(root, "tag"), assets)
    }

    private fun parseAssets(root: JsonObject, field: String): Map<String, ReleaseAsset> {
        val array = root.getAsJsonArray(field) ?: error("GitHub release response has no $field array")
        return buildMap {
            for (element in array) {
                require(element.isJsonObject) { "GitHub release asset is not an object" }
                val asset = element.asJsonObject
                val name = requiredString(asset, "name")
                put(name, ReleaseAsset(name, requiredString(asset, "browser_download_url")))
            }
        }
    }

    private fun allowedAssetUrl(asset: ReleaseAsset): String {
        val uri = URI.create(asset.url)
        require(uri.scheme.equals("https", ignoreCase = true) && uri.host.equals("github.com", ignoreCase = true)) {
            "Refusing non-HTTPS GitHub asset URL for ${asset.name}"
        }
        require(uri.path.startsWith("/$repository/releases/download/")) {
            "Refusing asset URL outside $repository for ${asset.name}"
        }
        return asset.url
    }

    private fun requiredString(root: JsonObject, field: String): String {
        val value = root.get(field)
        require(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isString) {
            "Missing string field: $field"
        }
        return value.asString.trim().also { require(it.isNotEmpty()) { "Empty string field: $field" } }
    }

    private fun parseObject(bytes: ByteArray, description: String): JsonObject =
        try {
            JsonParser.parseString(bytes.toString(StandardCharsets.UTF_8)).asJsonObject
        } catch (failure: Exception) {
            throw IllegalStateException("Invalid $description", failure)
        }

    private fun releaseApiUrl(): String = "https://api.github.com/repos/$repository/releases/latest"

    private fun safeTag(tag: String): String {
        require(TAG_PATTERN.matches(tag)) { "Invalid GitHub release tag" }
        return tag
    }

    private fun moveAtomically(source: Path, target: Path) {
        try {
            Files.move(source, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source, target, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private data class Release(val tag: String, val assets: Map<String, ReleaseAsset>)
    private data class ReleaseAsset(val name: String, val url: String)
    private data class Manifest(val tag: String, val assets: Map<String, ManifestAsset>)
    private data class ManifestAsset(val name: String, val sha256: String)
    private data class CacheMetadata(
        val tag: String,
        val assetName: String,
        val sha256: String,
        val relativePath: String,
    )
    private data class CachedBinary(val metadataPath: Path, val binaryPath: Path)

    companion object {
        const val DEFAULT_REPOSITORY = "tchivs/fathom-sql"
        const val MANIFEST_ASSET_NAME = "fathom-lsp-manifest.json"
        const val MANIFEST_SCHEMA_VERSION = 1
        const val METADATA_FILE_NAME = "latest.json"
        const val CACHE_TTL_MILLIS: Long = 24L * 60L * 60L * 1000L
        private const val MAX_RESPONSE_BYTES = 64 * 1024 * 1024
        private val SHA256_PATTERN = Regex("[0-9a-fA-F]{64}")
        private val TAG_PATTERN = Regex("[A-Za-z0-9._-]+")

        fun defaultCacheDirectory(): Path {
            val home = Paths.get(System.getProperty("user.home"))
            val os = System.getProperty("os.name").lowercase(Locale.ROOT)
            return when {
                os.contains("windows") -> Paths.get(System.getenv("LOCALAPPDATA") ?: home.resolve("AppData/Local").toString())
                    .resolve("Fathom/fathom-sql")
                os.contains("mac") || os.contains("darwin") -> home.resolve("Library/Caches/Fathom/fathom-sql")
                else -> Paths.get(System.getenv("XDG_CACHE_HOME") ?: home.resolve(".cache").toString())
                    .resolve("fathom/fathom-sql")
            }
        }

        private fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
                "%02x".format(Locale.ROOT, it)
            }

        private fun sha256(path: Path): String {
            val digest = MessageDigest.getInstance("SHA-256")
            Files.newInputStream(path).use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it) }
        }
    }

    private class UrlConnectionTransport : NativeHttpTransport {
        override fun get(url: String): ByteArray {
            val connection = (URI.create(url).toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = true
                connectTimeout = 15_000
                readTimeout = 120_000
                setRequestProperty("Accept", "application/json, application/octet-stream")
                setRequestProperty("User-Agent", "Fathom-IntelliJ/0.1")
            }
            try {
                val status = connection.responseCode
                if (status !in 200..299) {
                    throw IOException("HTTP $status while downloading $url")
                }
                return connection.inputStream.use { readBounded(it) }
            } finally {
                connection.disconnect()
            }
        }

        private fun readBounded(input: InputStream): ByteArray {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > MAX_RESPONSE_BYTES) {
                    throw IOException("Download exceeds ${MAX_RESPONSE_BYTES} bytes")
                }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        }
    }
}
