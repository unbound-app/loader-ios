plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repositoryRoot: File = rootDir.parentFile.parentFile
val packageVersion: String = repositoryRoot.resolve("packages/ios/control").readLines()
    .first { it.startsWith("Version:") }
    .substringAfter(":")
    .trim()
val buildNumber = providers.gradleProperty("unboundBuildNumber").orNull?.toIntOrNull()
val packageVersionCode = packageVersion.split(".").take(3).fold(0) { code, part ->
    code * 100 + (part.filter(Char::isDigit).toIntOrNull() ?: 0)
}
val resolvedVersionCode = buildNumber?.let { 1_000_000 + it } ?: packageVersionCode.coerceAtLeast(1)
val signingStoreFile = System.getenv("ANDROID_SIGNING_STORE_FILE")
val signingStorePassword = System.getenv("ANDROID_SIGNING_STORE_PASSWORD")
val signingKeyAlias = System.getenv("ANDROID_SIGNING_KEY_ALIAS")
val signingKeyPassword = System.getenv("ANDROID_SIGNING_KEY_PASSWORD")
val releaseSigningValues = listOf(signingStoreFile, signingStorePassword, signingKeyAlias, signingKeyPassword)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }

if (releaseSigningValues.any { !it.isNullOrBlank() } && !hasReleaseSigning) {
    throw GradleException("Android release signing requires all ANDROID_SIGNING_* values")
}

android {
    namespace = "app.unbound.android"
    compileSdk = 36
    ndkVersion = "27.3.13750724"

    defaultConfig {
        applicationId = "app.unbound.android"
        minSdk = 28
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = packageVersion

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_static", "-DUNBOUND_VERSION=$packageVersion")
                cppFlags += listOf("-std=c++20", "-fexceptions", "-frtti")
            }
        }

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    if (hasReleaseSigning) {
        signingConfigs {
            create("release") {
                storeFile = file(signingStoreFile!!)
                storePassword = signingStorePassword
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles("proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets["main"].assets.srcDirs(layout.buildDirectory.dir("generated/unbound-assets"))

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            merges += "META-INF/xposed/*"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

val copyBootstrapResources by tasks.registering(Copy::class) {
    from(repositoryRoot.resolve("packages/resources")) {
        include("*.js")
    }
    into(layout.buildDirectory.dir("generated/unbound-assets/js"))
}

tasks.named("preBuild") {
    dependsOn(copyBootstrapResources)
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    compileOnly("io.github.libxposed:api:102.0.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
