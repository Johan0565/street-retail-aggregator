allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
buildscript {
    extra["yandexMapkitVersion"] = "4.3.1-full" // <--- ДОБАВИТЬ ЭТУ СТРОКУ
    repositories {
        google()
        mavenCentral()
    }
    // ...
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
