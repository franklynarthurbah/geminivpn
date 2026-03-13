@if "%DEBUG%"=="" @echo off
@rem Gradle startup script for Windows
set DIRNAME=%~dp0
java -classpath "%DIRNAME%\gradle\wrapper\gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain %*
