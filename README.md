# qnd_updater

Flutter плагин для обновления приложений на Android, Windows, macOS и Linux. Проверяет новые версии через GitHub Releases, скачивает ZIP-архив под нужную платформу, распаковывает его и передает нативному коду для установки. Не требует сторонних сервисов, работает на чистом GitHub Releases.

## Возможности

- Проверка последней версии через GitHub Releases API
- Сравнение версий в формате semver (1.2.3) с нормализацией (убирается префикс `v` и суффикс `+build`)
- Скачивание одного ZIP-архива на платформу вместо сотен мелких файлов
- Отображение прогресса загрузки
- Полностью нативное применение обновления без внешних зависимостей
- Корректная распаковка `.app` на macOS с сохранением симлинков и прав
- Автоматическое снятие карантина при установке и обновлении на macOS
- Установочный DMG с готовым скриптом для пользователя
- Поддержка Android, Windows, macOS и Linux из одной кодовой базы

## Поддерживаемые платформы

| Платформа | Формат ассета | Способ установки |
|-----------|---------------|------------------|
| Android | `qnd_updater-<tag>-android.zip` | ZIP распаковывается, APK передается системному установщику |
| Windows | `qnd_updater-<tag>-windows.zip` | ZIP распаковывается в staging, helper .bat копирует файлы и перезапускает |
| macOS | `qnd_updater-<tag>-macos.zip` | ZIP распаковывается через `ditto`, helper .sh копирует `Contents` и перезапускает |
| Linux | `qnd_updater-<tag>-linux.zip` | ZIP распаковывается в staging, helper .sh копирует файлы и перезапускает |

Дополнительно в релиз кладутся файлы для ручной установки: `.apk`, `.exe`, `.dmg`, `.AppImage`, `.deb`.

## Установка

Добавьте плагин в `pubspec.yaml`:

```yaml
dependencies:
  qnd_updater:
    git:
      url: https://github.com/efedotof/qnd_updater.git
      ref: main
```

Или через локальный путь:

```yaml
dependencies:
  qnd_updater:
    path: ../qnd_updater
```

Обязательные зависимости плагина:

```yaml
dependencies:
  archive: ^4.3.0
  http: ^1.6.0
```

Плагин использует `archive` для распаковки ZIP на Windows/Linux/Android и `http` для запросов к GitHub. На macOS распаковка идет через системный `ditto`, чтобы сохранить симлинки внутри `.app`.

## Настройка приложения

### Android

#### 1. Разрешения

Добавьте в `android/app/src/main/AndroidManifest.xml` вашего приложения:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Разрешение `REQUEST_INSTALL_PACKAGES` нужно указывать именно в манифесте приложения, а не в манифесте плагина.

#### 2. FileProvider

Внутри тега `<application>` добавьте провайдер:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

Обратите внимание на `authorities`. В плагине используется `${packageName}.qnd_updater.fileprovider`, если вы не переопределяете. Проверьте соответствие в `QndUpdaterPlugin.kt`.

#### 3. Пути для FileProvider

Создайте `android/app/src/main/res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <external-cache-path name="ext_cache" path="." />
    <files-path name="files" path="." />
    <external-files-path name="ext_files" path="." />
</paths>
```

#### 4. Подпись

Приложение должно быть подписано release-ключом, иначе система откажется устанавливать поверх него новую версию. Настройте `android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystorePropertiesExists = keystorePropertiesFile.exists()
if (keystorePropertiesExists) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesExists) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let {
                    rootProject.file(it as String)
                }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (keystorePropertiesExists) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

Файл `android/key.properties` не должен попадать в git:

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=upload-keystore.jks
```

Ключевой момент: `rootProject.file(it)` резолвит путь относительно `android/`, а не относительно `android/app/`. Keystore кладите рядом с `key.properties`, в `android/upload-keystore.jks`. Без префикса `../` в значении `storeFile`.

### Windows

Ничего специально настраивать не нужно. Windows не использует песочницу для desktop-приложений, исходящие сетевые соединения разрешены по умолчанию.

Приложение должно иметь право записи в свою директорию. Не устанавливайте в `C:\Program Files`, если не готовы запускать с правами администратора. Тестируйте обновление из пользовательской папки, например `C:\Users\<user>\qnd_test\`.

### macOS

> **УСТАНОВКА.** Скачайте DMG, откройте, кликните **правой кнопкой** по `Установить.command` - «Открыть» - подтвердите. Всё остальное скрипт сделает сам, включая снятие карантина. Автообновление потом работает без каких-либо действий с вашей стороны.

Четыре обязательных пункта для разработчика.

#### 1. Разрешение на сеть и отключенная песочница

macOS запускает приложения в песочнице только если она явно включена ключом `com.apple.security.app-sandbox`. Для автообновления песочница должна быть выключена, иначе приложение не сможет писать в свою же директорию в `/Applications`, и `applyUpdate` завершится ошибкой при попытке заменить бандл.

В Flutter-проектах по умолчанию песочница не включена, но ее легко добавить случайно, например при копировании шаблона из другого проекта. Проверьте оба файла:

`macos/Runner/DebugProfile.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

`macos/Runner/Release.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Ключевые моменты:

- `com.apple.security.network.client` нужен для запросов к `api.github.com`. Без него падает с `SocketException`
- `com.apple.security.cs.allow-jit` нужен для работы Dart VM
- `com.apple.security.app-sandbox` не должен присутствовать. Если он есть, удалите. Sandbox ломает автообновление: процесс не сможет заменить свой же `.app` в `/Applications`, потому что sandbox разрешает запись только в `~/Library/Containers/<bundle-id>/`

Проверить, что ключ попал в собранный бандл и что sandbox отсутствует:

```bash
codesign -d --entitlements :- /path/to/Your.app | grep -E 'network|sandbox'
```

Ожидаемый вывод:

```
[Dict]
    [Key] com.apple.security.cs.allow-jit
    [Key] com.apple.security.network.client
```

Если увидите `com.apple.security.app-sandbox`, приложение в песочнице, автообновление работать не будет.

Если приложение запускается из `/Applications` и пытается себя обновить, ему нужны права на запись в `/Applications`. Если папка принадлежит другому пользователю (например, создана под root), `ditto` и `mv` в helper-скрипте упадут с `Permission denied`. В этом случае пользователь должен либо дать права на `/Applications/YourApp.app` для своей учетки, либо устанавливать приложение в `~/Applications`.

#### 2. Pin path_provider_foundation до 2.5.1

Версия 2.6.0 пакета `path_provider_foundation` использует FFI-реализацию через пакет `objective_c`, которая не загружается в release-сборке macOS:

```
Couldn't resolve native function 'DOBJC_initializeApi' in
'package:objective_c/objective_c.dylib'
```

Добавьте в `pubspec.yaml`:

```yaml
dependency_overrides:
  path_provider_foundation: 2.5.1
```

Версия 2.5.1 использует стабильный MethodChannel и этой проблемы не имеет. Пин действует на все платформы, но на Android, Windows и Linux это никак не сказывается.

#### 3. Распаковка `.app` через `ditto`

Внутри `.app` macOS лежат симлинки. Например, `App.framework/App` это симлинк на `Versions/Current/App`, и таких симлинков в бандле десятки. Dart-пакет `archive` при распаковке пишет симлинки как обычные текстовые файлы, из-за чего FlutterEngine не находит `flutter_assets` и `icudtl.dat`, и приложение падает при запуске с ошибкой:

```
Failed to find path for "flutter_assets"
Failed to find path for "icudtl.dat"
NSInvalidArgumentException: attempt to insert nil object from objects[0]
```

Чтобы этого не происходило, плагин на macOS распаковывает ZIP через системный `/usr/bin/ditto -x -k`, который корректно восстанавливает симлинки, executable-биты и xattr. После распаковки автоматически запускается проверка `_verifyStagedApp`, которая убеждается, что симлинки на месте, `flutter_assets` и `icudtl.dat` существуют, а бинарник имеет `+x`. Если что-то не так, обновление падает до установки, и пользователь не получает сломанный бандл.

Со стороны разработчика ничего делать не нужно, это работает из коробки. Но если вы форкаете плагин и переписываете распаковку, не заменяйте `ditto` обратно на `ZipDecoder`, если не готовы восстанавливать симлинки вручную.

#### 4. Установка на macOS для конечного пользователя

Без Apple Developer ID приложение нельзя подписать и нотаризовать, поэтому при первом запуске macOS показывает диалог «Приложение повреждено, переместите в Корзину». Это не повреждение, а Gatekeeper. Пользователю не нужно вручную возиться с терминалом и `xattr`, установочный скрипт делает это за него.

Плагин собирает DMG так, что приложение спрятано в скрытой папке `.payload` внутри образа, а рядом лежит исполняемый скрипт `Установить.command` и короткая инструкция `ПРОЧТИ_МЕНЯ.txt`. В окне DMG пользователь видит только скрипт, инструкцию и симлинк на `/Applications`. Приложение спрятано, чтобы его нельзя было перетащить вручную и наткнуться на Gatekeeper.

Как установить (инструкция для пользователя):

1. Откройте скачанный DMG двойным кликом.
2. Кликните правой кнопкой мыши (или `Control` + клик) по файлу `Установить.command` и выберите «Открыть» в контекстном меню.
3. Появится диалог с предупреждением. Это стандартное предупреждение macOS для скриптов из интернета, оно появляется один раз. Нажмите «Открыть» еще раз.
4. Скрипт сам скопирует приложение в `/Applications`, снимет карантин через `xattr -cr` и запустит приложение.
5. После этого приложение можно запускать двойным кликом как обычно. Все последующие автообновления проходят без участия пользователя, плагин снимает карантин с новой версии автоматически.

Если пользователь случайно перетащил `.app` из `.payload` в `/Applications` руками (продвинутые пользователи, которые включили показ скрытых файлов), и приложение не запускается, инструкция та же:

```bash
sudo xattr -cr /Applications/qnd_updater_example.app
```

или правой кнопкой по приложению, «Открыть», «Открыть».

Почему не просто «правый клик по .app»: если положить `.app` в корень DMG, пользователь сможет перетащить его в `/Applications` двойным кликом и получит предупреждение Gatekeeper при первом запуске. Скрытый `.payload` и скрипт убирают эту проблему, потому что пользователь физически не видит `.app` и не может сделать неправильно.

Чего это не решает:

- Приложение все равно не будет нотаризовано. При первом запуске скрипта пользователь видит предупреждение macOS для `.command`-файла (одно нажатие «Открыть»).
- При скачивании новой версии DMG вручную снова одно нажатие «Открыть» по скрипту. Но автообновление через `applyUpdate` этого не требует, плагин сам снимает карантин с новой версии после установки.

Полностью убрать все предупреждения можно только через Apple Developer ID (99 долларов в год) и нотаризацию.

### Linux

Зависимостей на стороне приложения нет, но для сборки нужны системные пакеты:

```bash
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libglu1-mesa
```

Для версии из GitHub Releases используйте один из форматов:

- AppImage: скачать `qnd_updater-<tag>-linux.AppImage`, выполнить `chmod +x` и запустить
- deb: скачать `qnd-updater-<version>-linux.deb`, установить через `sudo dpkg -i`
- zip: распаковать в папку с правом записи и запустить бинарник

Автообновление работает только для portable-раскладки (zip). Если приложение установлено через `.deb` в `/usr/lib/`, у процесса не будет прав на запись, и `applyUpdate` завершится ошибкой. Для установки в системную директорию обновление нужно запускать с правами root, что плагин не делает.

## Структура релиза на GitHub

Для каждой платформы публикуется ZIP с фиксированным именем:

```
qnd_updater-<tag>-android.zip
qnd_updater-<tag>-windows.zip
qnd_updater-<tag>-macos.zip
qnd_updater-<tag>-linux.zip
```

Тег в имени совпадает с тегом релиза, включая префикс `v`:

```
qnd_updater-v0.0.2-android.zip
qnd_updater-v0.0.2-windows.zip
qnd_updater-v0.0.2-macos.zip
qnd_updater-v0.0.2-linux.zip
```

Внутри архива:

- Android: `qnd_updater.apk` в корне архива
- Windows: содержимое папки `Release` в корне архива (`.exe`, `flutter_windows.dll`, `data/`)
- macOS: `Runner.app/Contents/...`
- Linux: содержимое `bundle` в корне архива (бинарник, `lib/`, `data/`)

Для ручной установки дополнительно кладутся:

- `qnd_updater-<tag>.apk`
- `qnd_updater-<tag>-windows.exe`
- `qnd_updater-<tag>-macos.dmg`
- `qnd_updater-<tag>-linux.AppImage`
- `qnd-updater-<version>-linux.deb`

Плагин не использует файлы для ручной установки, они только для пользователей.

## Использование

### Проверка обновления

```dart
import 'package:qnd_updater/qnd_updater.dart';

final updater = QndUpdater();

final status = await updater.checkForUpdate(
  githubToken: '',
  owner: 'your-org',
  repo: 'your-repo',
);

switch (status) {
  case UpdateStatus.updateAvailable:
    print('Доступна новая версия');
    break;
  case UpdateStatus.upToDate:
    print('Обновление не требуется');
    break;
  case UpdateStatus.error:
    print('Ошибка проверки обновления');
    break;
}
```

Если репозиторий публичный, `githubToken` можно оставить пустой строкой. Лимит запросов к GitHub API без токена составляет 60 в час на IP, с токеном 5000 в час.

Для приватного репозитория передайте personal access token с правами `Contents: Read-only`. Токен храните вне репозитория, например через `--dart-define` при сборке.

### Обновление на десктопе и Android

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qnd_updater/qnd_updater.dart';

Future<void> downloadAndApply() async {
  final updater = QndUpdater();
  final service = UpdaterService(owner: 'your-org', repo: 'your-repo');

  final platformKey = Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
          ? 'macos'
          : Platform.isLinux
              ? 'linux'
              : 'android';

  final tmp = await getTemporaryDirectory();
  final staging = Directory('${tmp.path}/qnd_staging');

  final result = await service.downloadUpdate(
    platformKey: platformKey,
    stagingDir: staging,
    onProgress: (done, total) {
      final percent = total > 0 ? (done * 100 / total).toStringAsFixed(1) : '0';
      debugPrint('Загружено $percent%');
    },
  );

  if (result == null) {
    debugPrint('Ассет для платформы $platformKey не найден');
    return;
  }

  await updater.applyUpdate(result.stagingDir.path);

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}
```

Дальнейшее поведение зависит от платформы:

- Android: открывается системный установщик, пользователь подтверждает установку
- Windows: текущий процесс завершается, helper .bat ждет выхода, копирует файлы, перезапускает приложение
- macOS: helper .sh ждет выхода процесса, копирует `Contents` бандла, снимает карантин, перезапускает
- Linux: helper .sh через `fork` и `setsid` ждет выхода процесса, копирует файлы, перезапускает

На десктопе после `applyUpdate` обязательно вызовите `exit(0)`, иначе helper будет ждать вечно.

## API

### QndUpdater

Основной класс.

| Метод | Описание |
|-------|----------|
| `getAppVersion()` | Возвращает текущую версию приложения |
| `checkForUpdate({githubToken, owner, repo})` | Проверяет наличие новой версии через GitHub |
| `applyUpdate(String path)` | Применяет обновление из staging директории |

### UpdateStatus

Результат проверки:

- `upToDate`: текущая версия актуальна
- `updateAvailable`: доступна новая версия
- `error`: ошибка проверки

### UpdaterService

Работа с GitHub Releases и скачиванием архива.

| Метод | Описание |
|-------|----------|
| `fetchLatestRelease()` | Возвращает информацию о последнем опубликованном релизе |
| `downloadUpdate({platformKey, stagingDir, onProgress})` | Скачивает ZIP для указанной платформы и распаковывает в staging директорию |
| `downloadLatest({platformKey, onProgress})` | Обертка над `downloadUpdate` с автоматическим выбором staging в `getTemporaryDirectory()` |

`platformKey` принимает значения `android`, `windows`, `macos`, `linux`.

`onProgress` вызывается при скачивании с текущим и общим количеством байт.

### UpdateResult

Результат скачивания:

- `version`: версия без префикса `v`
- `tag`: тег релиза как есть
- `stagingDir`: директория с распакованными файлами
- `totalBytes`: сколько байт скачано

## Как это работает

### Проверка обновления

1. Плагин получает версию приложения через нативный метод `getAppVersion`
2. Запрашивает последний релиз через `GET /repos/{owner}/{repo}/releases/latest`
3. Нормализует обе версии: убирает префикс `v` и суффикс `+build`
4. Сравнивает числа `major.minor.patch`

Черновики (draft) релизов через `/releases/latest` не возвращаются. Если видите 404, проверьте, опубликован ли релиз.

### Скачивание обновления

1. Плагин формирует имя ассета `qnd_updater-<tag>-<platform>.zip`
2. Ищет его в списке ассетов последнего релиза
3. Скачивает с прогрессом в staging директорию
4. Распаковывает ZIP:
   - macOS: через `/usr/bin/ditto -x -k` (сохраняет симлинки)
   - остальные платформы: через `ZipDecoder` из пакета `archive`
5. На macOS запускает `_verifyStagedApp`, проверяет, что `.app` распакован корректно
6. Удаляет временный ZIP
7. Возвращает `UpdateResult`

### Применение обновления

Поведение зависит от платформы.

Android. Плагин ищет `.apk` в staging директории, получает URI через `FileProvider`, открывает системный установщик через `Intent.ACTION_VIEW`.

Windows. Плагин создает helper `.bat` в `%TEMP%`. Helper ждет, пока процесс завершится (через `tasklist`), копирует файлы из staging в директорию приложения через `xcopy`, запускает приложение заново, удаляет себя.

macOS. Плагин создает helper `.sh`. Helper ждет выхода процесса (через `kill -0`), копирует содержимое `Contents/` из staging `.app` в текущий бандл через `ditto`, снимает карантин, перезапускает приложение.

Linux. Плагин создает helper `.sh`, запускает его через `fork` и `setsid`, чтобы он жил после выхода процесса. Helper ждет выхода (через `kill -0`), копирует файлы из staging в директорию приложения, запускает бинарник через `nohup`, удаляет себя.

## Настройка CI для автообновления

Этот раздел для тех, кто делает форк плагина или хочет построить свой CI с автообновлением через GitHub Releases. Готовый workflow лежит в репозитории в `.github/workflows/Release.yml`, здесь разобраны ключевые моменты.

### Триггер по тегу

Workflow запускается по пушу тега вида `v*`:

```yaml
on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write
```

`permissions.contents: write` обязателен, иначе `softprops/action-gh-release` не сможет создать релиз.

Тег должен указывать на тот же коммит, что и ветка `main`. Если сделать тег от старого коммита, CI соберет старую версию. Проверить:

```bash
git log --oneline -1 v0.0.2
git log --oneline -1 main
```

### Версия в pubspec.yaml

Перед созданием тега обновите версию в `example/pubspec.yaml` и в `example/macos/Runner/Info.plist` (для `CFBundleShortVersionString` и `CFBundleVersion`):

```yaml
version: 0.0.3+3
```

Плагин читает версию через `getAppVersion` из `Info.plist` на macOS, из `build.gradle` на Android, из ресурсов на Windows и Linux. Все версии должны совпадать, иначе проверка обновления будет некорректной.

### Универсальный бинарник macOS

macOS собирается в два прогона, чтобы получить universal бинарник для Intel и Apple Silicon:

```yaml
- name: Build arm64
  working-directory: example
  env:
    FLUTTER_XCODE_ARCHS: arm64
  run: |
    flutter pub get
    flutter build macos --release

- name: Save arm64 app
  run: |
    mkdir -p /tmp/arm
    cp -R example/build/macos/Build/Products/Release/*.app /tmp/arm/Runner.app

- name: Clean for x86_64 build
  working-directory: example
  run: |
    flutter clean
    flutter pub get

- name: Build x86_64
  working-directory: example
  env:
    FLUTTER_XCODE_ARCHS: x86_64
    FLUTTER_XCODE_ONLY_ACTIVE_ARCH: "NO"
  run: flutter build macos --release
```

Затем `lipo -create` сливает бинарники всех фреймворков:

```bash
for fw in "$U/Contents/Frameworks/"*.framework; do
  name=$(basename "$fw" .framework)
  bin="$fw/Versions/A/$name"
  [ -f "$bin" ] || bin="$fw/$name"
  a="/tmp/arm/Runner.app/Contents/Frameworks/$name.framework/Versions/A/$name"
  i="/tmp/intel/Runner.app/Contents/Frameworks/$name.framework/Versions/A/$name"
  if [ -f "$a" ] && [ -f "$i" ]; then
    lipo -create "$a" "$i" -output "$bin"
  fi
done
```

Пропустить этот шаг можно, если публикуете только для одной архитектуры, но тогда пользователи на другой не смогут запустить приложение.

### Ad-hoc подпись

Без Apple Developer ID используйте ad-hoc подпись. Это не убирает предупреждение Gatekeeper, но позволяет приложению запускаться на Apple Silicon, где macOS требует хотя бы минимальной подписи.

```yaml
- name: Sign app with release entitlements
  run: |
    codesign --force --deep --sign - \
      --entitlements /tmp/release.entitlements \
      /tmp/universal/Runner.app
```

Перед подписью удалите старые `_CodeSignature`:

```bash
find /tmp/universal/Runner.app -type d -name "_CodeSignature" -prune -exec rm -rf {} + 2>/dev/null || true
```

### Упаковка ZIP с сохранением симлинков

Для macOS ZIP собирается через `ditto`, а не через `zip`. Обычный `zip` превращает симлинки в обычные файлы, и приложение падает с `Failed to find path for "flutter_assets"`.

```yaml
- name: Package zip with ditto (preserves xattrs)
  run: |
    mkdir -p dist
    cd /tmp/universal
    ditto -c -k --rsrc --extattr --keepParent Runner.app \
      "$GITHUB_WORKSPACE/dist/qnd_updater-${{ github.ref_name }}-macos.zip"
```

Если используете `zip`, обязателен флаг `-y` для сохранения симлинков:

```bash
zip -qry archive.zip Runner.app
```

Но `ditto` надежнее для `.app`.

### DMG с установочным скриптом

Шаг сборки DMG описан в разделе macOS. Ключевое отличие от стандартного DMG: приложение уезжает в скрытую папку `.payload`, а рядом кладется исполняемый скрипт `Установить.command`, который копирует приложение в `/Applications` и снимает карантин.

Скрыть `.payload` можно двумя способами. Первый: точка в начале имени, это работает всегда. Второй: дополнительный флаг `SetFile -a V`, который ставит атрибут invisible поверх:

```bash
SetFile -a V /tmp/dmg/.payload || true
```

`SetFile` входит в Xcode Command Line Tools, на macOS-раннерах GitHub Actions он доступен. `|| true` защищает от падения, если утилита недоступна.

### Публикация релиза

```yaml
- uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}
    generate_release_notes: true
    files: |
      dist/*.zip
      dist/*.apk
      dist/*.exe
      dist/*.dmg
      dist/*.deb
      dist/*.AppImage
```

Не используйте `draft: true`. Плагин обращается к `/releases/latest`, а этот эндпоинт не возвращает черновики. Если оставить `draft: true`, плагин получит 404 и не увидит обновление.

### Проверка перед публикацией

Полезно добавить шаг, который монтирует готовый DMG и убеждается, что структура правильная, до публикации релиза:

```yaml
- name: Verify dmg contents
  run: |
    set -e
    rm -rf /tmp/verify_dmg
    mkdir -p /tmp/verify_dmg
    hdiutil attach \
      "$GITHUB_WORKSPACE/dist/qnd_updater-${{ github.ref_name }}-macos.dmg" \
      -mountpoint /tmp/verify_dmg -nobrowse
    ls -la /tmp/verify_dmg
    ls -la /tmp/verify_dmg/.payload
    codesign --verify --verbose=2 \
      "/tmp/verify_dmg/.payload/qnd_updater_example.app"
    hdiutil detach /tmp/verify_dmg
```

Это ловит регрессии в CI, например случайную замену `ditto` на `zip` или потерю прав.

## Как писать приложение с автообновлением

Этот раздел для разработчиков, которые используют `qnd_updater` в своих проектах. Он не про сам плагин, а про то, как построить приложение так, чтобы автообновление работало надежно.

### Именование ассетов

Плагин ищет ассет по фиксированному шаблону: `qnd_updater-<tag>-<platform>.zip`, где `<platform>` это `android`, `windows`, `macos` или `linux`. Если ваше приложение называется иначе, задайте другой шаблон в `_assetNameFor` в `lib/src/updater_service.dart`:

```dart
String _assetNameFor(String platformKey, String tag) {
  final cleanTag = tag.startsWith('v') ? tag : 'v$tag';
  return 'myapp-$cleanTag-$platformKey.zip';
}
```

Или передайте префикс через конструктор `UpdaterService`, если добавите такое поле. Главное, чтобы имя ассета в релизе совпадало с тем, что ожидает плагин. Проверить можно так:

```bash
curl -s https://api.github.com/repos/your-org/your-repo/releases/latest \
  | grep '"name"'
```

### Публикация релиза

Релиз должен быть опубликован, не draft. Тег должен указывать на тот коммит, из которого собраны артефакты. Если тег и билд расходятся, пользователь получит обновление на версию, которая не соответствует исходникам.

Минимальный чек-лист перед созданием тега:

1. Обновите `version` в `pubspec.yaml` приложения и плагина
2. Обновите `CFBundleShortVersionString` и `CFBundleVersion` в `macos/Runner/Info.plist`
3. Обновите `versionCode` и `versionName` в `android/app/build.gradle.kts`
4. Обновите `kDemoBuildTag` в тестовом экране, если он есть
5. Убедитесь, что `flutter analyze` проходит без ошибок
6. Запушьте коммит в `main`, создайте тег, запушьте тег
7. Дождитесь, пока CI соберет все платформы и опубликует релиз
8. Проверьте страницу релиза, все ассеты на месте

### Проверка обновления в приложении

Не вызывайте `checkForUpdate` при каждом старте приложения. GitHub API имеет лимит 60 запросов в час без токена. Если у пользователя несколько устройств или он часто перезапускает приложение, лимит быстро закончится, и проверка начнет падать с ошибкой 403.

Разумные варианты:

- Проверять раз в сутки при запуске, сохраняя дату последней проверки в `SharedPreferences`
- Проверять по кнопке в UI
- Проверять при старте, но оборачивать в try/catch и игнорировать ошибки сети

Пример с сохранением даты последней проверки:

```dart
Future<void> checkUpdateIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final lastCheck = prefs.getInt('last_update_check') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  const dayMs = 24 * 60 * 60 * 1000;

  if (now - lastCheck < dayMs) {
    return;
  }

  try {
    final status = await QndUpdater().checkForUpdate(
      githubToken: '',
      owner: 'your-org',
      repo: 'your-repo',
    );
    if (status == UpdateStatus.updateAvailable) {
      // показать баннер или диалог
    }
    await prefs.setInt('last_update_check', now);
  } catch (e) {
    debugPrint('Ошибка проверки обновления: $e');
  }
}
```

### Сценарий обновления с точки зрения пользователя

Правильный UX автообновления:

1. Пользователь запускает приложение, в фоне идет проверка версии
2. Если обновление есть, показывается ненавязчивый баннер «Доступна версия X.Y.Z» с кнопкой «Обновить»
3. Пользователь нажимает кнопку, показывается прогресс загрузки
4. После загрузки приложение предупреждает «Приложение будет перезапущено» и через 2 секунды завершается
5. Helper-скрипт заменяет бандл и запускает приложение заново
6. После перезапуска пользователь видит новую версию

Не запускайте `applyUpdate` автоматически без согласия пользователя. Это плохой UX: пользователь может быть посреди работы, а приложение внезапно закроется.

### Обязательный exit(0)

После `applyUpdate` на десктопе обязательно вызовите `exit(0)`. Без этого helper-скрипт будет ждать завершения процесса вечно, потому что Flutter не всегда закрывает нативные ресурсы сразу после `Navigator.pop` или `SystemNavigator.pop`. `exit(0)` гарантированно завершает процесс.

На Android `exit(0)` не нужен. Системный установщик сам откроется, а пользователь подтвердит установку. После подтверждения текущий процесс будет убит системой.

### Обработка ошибок сети

`checkForUpdate` возвращает `UpdateStatus.error` при любой сетевой проблеме. Не показывайте это пользователю как ошибку. Логируйте через `debugPrint` и продолжайте работу приложения. Пользователь сам решит, когда проверить обновление снова.

Типичные причины `error`:

- Нет интернета
- Лимит GitHub API исчерпан (60 в час без токена)
- Репозиторий приватный, а токен не передан
- Релиз в статусе draft
- Тег в релизе не совпадает с ожидаемым шаблоном

Если ошибка повторяется стабильно, проверьте:

```bash
curl -i https://api.github.com/repos/your-org/your-repo/releases/latest
```

### Тестирование автообновления

Тестировать автообновление нужно на всех платформах, потому что поведение отличается. Схема такая:

1. Соберите версию 0.0.1 с `kDemoBuildTag = 'build-001'`, установите на устройство или в виртуальную машину
2. Поменяйте `kDemoBuildTag` на `build-002`, обновите версию в `pubspec.yaml`, создайте тег `v0.0.2`, запушьте
3. Дождитесь релиза в CI
4. В приложении нажмите «Check for update», затем «Download and apply»
5. Проверьте, что приложение перезапустилось и баннер показывает `build-002`

Особенно тщательно тестируйте macOS, потому что там больше всего подводных камней: симлинки, карантин, entitlements, универсальный бинарник.

## GitHub Actions

Полный workflow лежит в репозитории. Здесь только скелет для ориентира.

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

env:
  FLUTTER_VERSION: '3.47.5'
```

### Важные моменты

- Universal macOS собирается через два прогона `flutter build macos` с разными `FLUTTER_XCODE_ARCHS` (arm64 и x86_64), затем `lipo` сливает бинарники
- На macOS в CI не забудьте `flutter config --enable-native-assets` из-за `objective_c`
- Тег должен указывать на тот же коммит, что и ветка. Иначе CI соберет старую версию
- Не используйте `draft: true` в `action-gh-release`, иначе плагин не увидит релиз через `/releases/latest`
- `ditto -c -k --rsrc --extattr` сохраняет xattr и симлинки при упаковке ZIP для macOS, обычный `zip` их ломает

## Ограничения

Android. Тихая установка без диалога невозможна. Система требует подтверждения пользователя. Публикация в Google Play не позволяет обновлять APK через сторонние источники, ограничение действует на уровне политики магазина.

macOS. Песочница (app sandbox) должна быть выключена, иначе приложение не сможет заменить свой же бандл при автообновлении. Приложение должно быть собрано с entitlements `com.apple.security.network.client`, без него сеть недоступна. DMG содержит установочный скрипт `Установить.command`, который копирует приложение и снимает карантин. Все последующие автообновления проходят без участия пользователя, потому что `applyUpdate` снимает карантин с новой версии автоматически. Полностью убрать предупреждение Gatekeeper можно только через Apple Developer ID и нотаризацию.

Windows. Приложение должно иметь право записи в свою директорию. Не устанавливайте в `C:\Program Files`, если не готовы запускать с правами администратора.

Linux. Обновление работает только для portable-раскладки. Если приложение установлено через `.deb` в `/usr/lib`, у процесса нет прав на запись. AppImage обновлять тоже нетривиально, нужен отдельный подход.

## Диагностика

### GitHub вернул 404

Скорее всего релиз в статусе draft. Откройте GitHub Releases и опубликуйте его. `/releases/latest` не возвращает черновики.

### SocketException на macOS

Не добавлен ключ `com.apple.security.network.client` в entitlements. Проверьте оба файла, `DebugProfile.entitlements` и `Release.entitlements`.

### macOS: applyUpdate падает с Permission denied

Проверьте, что в entitlement'ах нет ключа `com.apple.security.app-sandbox`. Sandbox разрешает запись только в контейнер приложения и запрещает менять файлы в `/Applications`. Уберите ключ из обоих файлов (`DebugProfile.entitlements` и `Release.entitlements`) и пересоберите приложение.

Проверить, что sandbox выключен:

```bash
codesign -d --entitlements :- /Applications/YourApp.app | grep sandbox
```

Команда не должна ничего вывести.

### Couldn't resolve native function 'DOBJC_initializeApi'

Проблема с `path_provider_foundation 2.6.0` на macOS. Добавьте в `pubspec.yaml`:

```yaml
dependency_overrides:
  path_provider_foundation: 2.5.1
```

### macOS: Failed to find path for "flutter_assets"

Симлинки внутри `.app` были сломаны распаковкой. Проверьте, что в `UpdaterService.downloadUpdate` на macOS используется `ditto`, а не `ZipDecoder`:

```bash
ls -la /Applications/YourApp.app/Contents/Frameworks/App.framework/
```

Должны быть строки вида `lrwxr-xr-x App -> Versions/Current/App`. Если видите `-rw-r--r-- App`, симлинк превратился в файл. Обновите плагин до версии с `ditto` в `downloadUpdate`.

### macOS: permission denied при запуске .app

Бинарник потерял `+x` при распаковке. Снять карантин и поставить права вручную:

```bash
sudo chmod +x /Applications/YourApp.app/Contents/MacOS/YourApp
sudo xattr -cr /Applications/YourApp.app
```

Если повторяется при каждом обновлении, распаковка снова идет через `ZipDecoder`, а не через `ditto`.

### macOS: приложение повреждено после установки из DMG

Gatekeeper. Откройте DMG и запустите `Установить.command` через правый клик, «Открыть». Скрипт сам снимет карантин. Если хотите сделать вручную:

```bash
sudo xattr -cr /Applications/YourApp.app
```

### APK not found на Android

Проверьте имя ассета в релизе. Плагин ищет `qnd_updater-<tag>-android.zip`. Внутри архива должен быть `qnd_updater.apk`.

### Keystore not found при сборке

Если используете `rootProject.file(it)` в `build.gradle.kts`, в `key.properties` должно быть `storeFile=upload-keystore.jks` без префикса `../`, а сам keystore лежать в `android/upload-keystore.jks`.

Если используете `file(it)`, в `key.properties` должно быть `storeFile=../upload-keystore.jks`, keystore в `android/upload-keystore.jks`.

### type '_Uint8ArrayView' is not a subtype of type 'Stream<List<int>>'

Старый код распаковки. Обновите `UpdaterService.downloadUpdate`, используется `writeAsBytes(file.content as List<int>)` вместо каста к Stream.

## Пример приложения

В папке `example/` есть демонстрационное приложение со всеми платформами. В `example/lib/test.dart` определены константы `kDemoBuildTag` и `kDemoChangelog`. Меняйте их перед каждым релизом, чтобы визуально проверить, что обновление действительно применено.

Порядок тестирования:

1. Соберите `v0.0.1` с `kDemoBuildTag = 'build-001'`, установите на устройство
2. Поменяйте на `build-002`, обновите версию в `pubspec.yaml`, сделайте тег `v0.0.2`
3. Дождитесь релиза в CI
4. На устройстве нажмите Check for update, затем Download and apply
5. После перезапуска баннер должен показывать `build-002`

## Лицензия

Проект распространяется под лицензией MIT.

Вы можете свободно:

- использовать плагин в коммерческих и некоммерческих проектах
- изменять исходный код под свои задачи
- распространять плагин и производные работы
- включать плагин в закрытые приложения

При условии, что в исходниках или документации сохраняется уведомление об авторских правах и текст лицензии.

Полный текст лицензии в файле [LICENSE](LICENSE) в корне репозитория.

## Вклад в проект

Если нашли баг или хотите предложить улучшение:

1. Откройте issue с описанием проблемы и шагами воспроизведения
2. Для правок сделайте форк, создайте ветку, внесите изменения
3. Убедитесь, что `flutter analyze` проходит без ошибок
4. Откройте pull request с описанием того, что меняете и зачем

Перед крупными изменениями лучше сначала открыть issue и обсудить подход, чтобы не переделывать работу дважды.