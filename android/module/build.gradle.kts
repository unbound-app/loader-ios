plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repositoryRoot: File = rootDir.parentFile
val packageVersion: String = repositoryRoot.resolve("ios/control").readLines()
    .first { it.startsWith("Version:") }
    .substringAfter(":")
    .trim()

android {
    namespace = "app.unbound.android"
    compileSdk = 36
    ndkVersion = "27.3.13750724"

    defaultConfig {
        applicationId = "app.unbound.android"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
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

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles("proguard-rules.pro")
            signingConfig = signingConfigs["debug"]
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets["main"].assets.srcDirs(layout.buildDirectory.dir("generated/unbound-assets"))

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
    from(repositoryRoot.resolve("resources")) {
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
}
