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
subprojects {
    val configureAndroid: (Project) -> Unit = { proj ->
        val android = proj.extensions.findByName("android")
        if (android != null) {
            for (m in android.javaClass.methods) {
                if ((m.name == "setCompileSdk" || m.name == "setCompileSdkVersion" || m.name == "compileSdkVersion") && m.parameterTypes.size == 1) {
                    val paramType = m.parameterTypes[0]
                    try {
                        if (paramType == java.lang.Integer::class.java || paramType == java.lang.Integer.TYPE) {
                            m.invoke(android, 36)
                        } else if (paramType == java.lang.String::class.java) {
                            m.invoke(android, "android-36")
                        }
                    } catch (_: Throwable) {}
                }
            }
        }
    }
    if (project.state.executed) {
        configureAndroid(project)
    } else {
        project.afterEvaluate { configureAndroid(project) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
