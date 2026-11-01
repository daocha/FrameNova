import com.android.build.api.artifact.SingleArtifact
import com.android.build.api.variant.BuiltArtifactsLoader
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}
// Debug builds can update from a server on your LAN (scripts/serve-dev-update.sh). The host comes from the
// gitignored .env at the repository root (or the environment), so no address is ever committed.
val dotEnv = providers.fileContents(layout.projectDirectory.file("../../.env")).asText.orNull.orEmpty()
    .lineSequence().map(String::trim).filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
    .associate { line -> line.substringBefore("=").removePrefix("export ").trim() to line.substringAfter("=").substringBefore(" #").trim().trim('"', '\'') }
fun devSetting(name: String) = providers.environmentVariable(name).orNull ?: dotEnv[name]
val devUpdateHost = devSetting("FRAMENOVA_DEV_UPDATE_HOST")?.takeIf(String::isNotBlank)?.also {
    require(Regex("^[A-Za-z0-9.-]+$").matches(it)) { "FRAMENOVA_DEV_UPDATE_HOST must be an IPv4 address or host name" }
}
val devUpdatePort = (devSetting("FRAMENOVA_DEV_UPDATE_PORT") ?: "8767").also {
    require(it.toIntOrNull() in 1..65535) { "FRAMENOVA_DEV_UPDATE_PORT must be a port number" }
}

android {
    namespace = "com.framenova.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.framenova.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["appLabel"] = "FrameNova"
        buildConfigField("String", "DEV_UPDATE_URL", "\"\"")
    }
    buildFeatures { compose = true; buildConfig = true }
    androidResources { localeFilters += listOf("en", "b+zh+Hant", "zh-rTW", "zh-rHK") }
    // Release signing comes only from the environment (set by scripts/_signing-common.sh); no key is ever committed.
    val releaseKeystore = System.getenv("FRAMENOVA_KEYSTORE_FILE")
    signingConfigs {
        if (releaseKeystore != null) create("release") {
            storeFile = file(releaseKeystore); storePassword = System.getenv("FRAMENOVA_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("FRAMENOVA_KEY_ALIAS"); keyPassword = System.getenv("FRAMENOVA_KEY_PASSWORD")
        }
    }
    buildTypes {
        // UPDATE_CHANNEL: "none" (debug without a LAN server), "lan" (debug with FRAMENOVA_DEV_UPDATE_HOST),
        // "github" (signed sideload APK), "play" (Google Play bundle).
        all { buildConfigField("String", "UPDATE_CHANNEL", "\"none\"") }
        // Own package name and label so the debug build installs next to (not over) a release build signed with another key.
        debug {
            applicationIdSuffix = ".debug"; versionNameSuffix = "-debug"; manifestPlaceholders["appLabel"] = "FrameNova Dev"
            if (devUpdateHost != null) {
                buildConfigField("String", "UPDATE_CHANNEL", "\"lan\"")
                buildConfigField("String", "DEV_UPDATE_URL", "\"http://$devUpdateHost:$devUpdatePort/\"")
            }
        }
        release {
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true; isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
            buildConfigField("String", "UPDATE_CHANNEL", "\"github\"")
        }
        // Upload this variant to Play. It updates through Play and has no APK-install permission.
        create("playRelease") {
            initWith(getByName("release")); matchingFallbacks += listOf("release")
            buildConfigField("String", "UPDATE_CHANNEL", "\"play\"")
        }
    }
    // The APK-install permission and the update FileProvider exist in debug only when a LAN update server is set.
    if (devUpdateHost != null) sourceSets.getByName("debug") {
        manifest.srcFile("src/lanUpdate/AndroidManifest.xml")
        res.srcDir("src/lanUpdate/res")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    lint { disable += listOf("UnsafeOptInUsageError", "MissingTranslation") }
}

androidComponents.onVariants(androidComponents.selector().withBuildType("debug")) { variant ->
    // Every debug build must count as newer than the installed one: seconds since 2026-01-01 UTC.
    val stamp = (System.currentTimeMillis() / 1000 - 1_767_225_600).toInt()
    variant.outputs.forEach { it.versionCode.set(stamp) }
    if (devUpdateHost == null) return@onVariants
    val network = tasks.register<LanNetworkConfig>("${variant.name}LanNetworkConfig") { host.set(devUpdateHost) }
    variant.sources.res?.addGeneratedSourceDirectory(network, LanNetworkConfig::outputDir)
    val publish = tasks.register<PublishLanUpdate>("${variant.name}PublishLanUpdate") {
        apkFolder.set(variant.artifacts.get(SingleArtifact.APK))
        loader.set(variant.artifacts.getBuiltArtifactsLoader())
        outputDir.set(rootProject.layout.projectDirectory.dir("dist/dev-update"))
    }
    tasks.matching { it.name == "assemble${variant.name.replaceFirstChar(Char::uppercase)}" }.configureEach { finalizedBy(publish) }
}

/** Lets the debug app use plain HTTP to the LAN update host and nowhere else. */
abstract class LanNetworkConfig : DefaultTask() {
    @get:Input abstract val host: Property<String>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @TaskAction fun write() {
        outputDir.get().file("xml/lan_update_network.xml").asFile.apply { parentFile.mkdirs() }.writeText("""
            <network-security-config>
                <domain-config cleartextTrafficPermitted="true"><domain includeSubdomains="false">${host.get()}</domain></domain-config>
            </network-security-config>
        """.trimIndent())
    }
}

/** Copies the debug APK to android/dist/dev-update with the latest.json and SHA256SUMS that the app reads. */
abstract class PublishLanUpdate : DefaultTask() {
    @get:InputFiles abstract val apkFolder: DirectoryProperty
    @get:Internal abstract val loader: Property<BuiltArtifactsLoader>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @TaskAction fun publish() {
        val built = loader.get().load(apkFolder.get()) ?: throw GradleException("No debug APK was built")
        val output = built.elements.single()
        val code = output.versionCode ?: throw GradleException("The debug APK has no version code")
        val directory = outputDir.get().asFile.apply { mkdirs() }
        val name = "FrameNova-debug-$code.apk"
        val apk = File(output.outputFile).copyTo(File(directory, name), overwrite = true)
        val sha = MessageDigest.getInstance("SHA-256").digest(apk.readBytes()).joinToString("") { "%02x".format(it) }
        File(directory, "FrameNova-debug-$code.SHA256SUMS").writeText("$sha  $name\n")
        val json = """{"versionCode":$code,"versionName":"${output.versionName.orEmpty()}","apk":"$name","size":${apk.length()}}"""
        File(directory, "latest.json.part").apply { writeText(json + "\n") }.renameTo(File(directory, "latest.json"))
        // Only now drop older builds, so latest.json never names a file that is missing.
        directory.listFiles()?.filter { it.name.startsWith("FrameNova-debug-") && !it.name.startsWith("FrameNova-debug-$code.") }
            ?.forEach { it.delete() }
        logger.lifecycle("LAN update: android/dist/dev-update/$name (versionCode $code)")
    }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    val media3 = "1.9.3"
    implementation(platform("androidx.compose:compose-bom:2025.12.01"))
    implementation("androidx.activity:activity-compose:1.12.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-effect:$media3")
    implementation("androidx.media3:media3-transformer:$media3")
    // In-app updates for Play installs (talks to the Play Store app).
    implementation("com.google.android.play:app-update:2.1.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
