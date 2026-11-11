@echo off
chcp 65001 >nul 2>&1
setlocal

rem 可移植构建脚本：不写死任何盘符，换机器也能直接跑。
rem 用法：在仓库根目录执行  tool\build_apk.bat
rem 产物：仓库根目录上一级的 wordlog-v<版本>-arm64.apk（版本号从 pubspec.yaml 读）

cd /d "%~dp0.."

where flutter >nul 2>&1
if errorlevel 1 (
  echo [x] 找不到 flutter。请先安装 Flutter，并把 flutter\bin 加入 PATH。
  exit /b 1
)

if "%ANDROID_HOME%"=="" if "%ANDROID_SDK_ROOT%"=="" (
  echo [x] 没设置 ANDROID_HOME 或 ANDROID_SDK_ROOT，指向 Android SDK 目录。
  exit /b 1
)
if "%ANDROID_HOME%"=="" set ANDROID_HOME=%ANDROID_SDK_ROOT%

if "%JAVA_HOME%"=="" (
  echo [!] 没设置 JAVA_HOME，将使用 PATH 里的 java。Gradle 通常要求 JDK 17+。
)

if not exist pubspec.yaml (
  echo [x] 当前目录没有 pubspec.yaml，请把脚本放在 wordlog\tool\ 下。
  exit /b 1
)

set VER=
for /f "usebackq tokens=1,2" %%a in (`findstr /b /c:"version:" pubspec.yaml`) do set VER=%%b
if "%VER%"=="" (
  echo [x] 没能从 pubspec.yaml 读到 version 行。
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%VER%") do set VERNAME=%%v
echo [i] 版本 %VERNAME%，开始构建 release APK...

call flutter build apk --release --target-platform android-arm64
if errorlevel 1 (
  echo [x] 构建失败，看上面的 Gradle 输出。
  exit /b 1
)

set OUT=..\wordlog-v%VERNAME%-arm64.apk
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%OUT%" >nul
if errorlevel 1 (
  echo [x] 构建成功但拷贝产物失败，APK 在 build\app\outputs\flutter-apk\app-release.apk
  exit /b 1
)

echo [ok] 已生成 %OUT%
endlocal
