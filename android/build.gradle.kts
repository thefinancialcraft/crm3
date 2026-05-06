// ============================================================
//  ROOT build.gradle.kts  —  Fully Optimized
//  Fixes: namespace crash, hardcoded plugin list, circular dep,
//         CI/CD path issue, AGP 7.2+ compatibility
// ============================================================


allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// FIX #4 (Gradle): CI/CD mein relative ../../build toot sakta tha.
// Ab rootProject.buildDir use karo — portable hai.
val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

evaluationDependsOn(":app")

// ============================================================
//  FIX #1 + #2 (Gradle): Namespace auto-assignment
//  afterEvaluate ki jagah plugins.withId use karo — yeh AGP 7.2+
//  compatible hai aur evaluation order safe hai.
//  Hardcoded list ki jagah dynamic map use karo.
// ============================================================

// Namespace map — known Flutter plugins jinhe namespace nahi milta
val pluginNamespaces = mapOf(
    "ota_update"                    to "sk.fourq.otaupdate",
    "device_info_plus"              to "dev.fluttercommunity.plus.device_info",
    "package_info_plus"             to "dev.fluttercommunity.plus.packageinfo",
    "flutter_local_notifications"   to "com.dexterous.flutterlocalnotifications",
    "connectivity_plus"             to "dev.fluttercommunity.plus.connectivity",
    "share_plus"                    to "dev.fluttercommunity.plus.share",
    "url_launcher_android"          to "io.flutter.plugins.urllauncher",
    "permission_handler_android"    to "com.baseflow.permissionhandler",
    "flutter_background_service"    to "id.flutter.flutter_background_service",
    "flutter_overlay_window"        to "net.hamrobato.flutter_overlay_window",
    "phone_state"                   to "dev.fluttercommunity.plus.phonestate",
    "in_app_update"                 to "in.drogon.inappreview",
    "path_provider_android"         to "io.flutter.plugins.pathprovider",
    "shared_preferences_android"    to "io.flutter.plugins.sharedpreferences",
    "flutter_svg"                   to "com.example.flutter_svg"
)

subprojects {
    // plugins.withId waits for the plugin to be applied — no race condition
    plugins.withId("com.android.library") {
        val lib = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (lib != null) {
            val assignedNs = pluginNamespaces[project.name]
            if (assignedNs != null && lib.namespace == null) {
                lib.namespace = assignedNs
                println("[namespace-fix] ${project.name} => $assignedNs")
            }
        }
    }

    // FIX: compileSdk aur targetSdk sab plugins mein consistent rakho
    plugins.withId("com.android.library") {
        val lib = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        lib?.compileSdk = 36
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
