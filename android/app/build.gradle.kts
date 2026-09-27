import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名配置读取：android/key.properties（本地，已 gitignore）
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

android {
    namespace = "com.thirdparty.zsgj.my_bus_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.thirdparty.zsgj.my_bus_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // 从 android/key.properties 读取（CI 由 workflow 生成，本地手动创建）
            val store = keystoreProperties.getProperty("storeFile")
            val storePass = keystoreProperties.getProperty("storePassword")
            val alias = keystoreProperties.getProperty("keyAlias")
            val keyPass = keystoreProperties.getProperty("keyPassword")
            if (store != null && storePass != null && alias != null && keyPass != null) {
                storeFile = file(store) // 相对 android/app 解析
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            // 配置了正式签名则使用，否则回退 debug 签名（保证 flutter run --release 可用）
            val releaseConfig = signingConfigs.getByName("release")
            signingConfig = if (releaseConfig.storeFile != null) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
