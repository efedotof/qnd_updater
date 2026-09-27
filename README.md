# qnd_updater

Flutter плагин для обновления приложений на Android, Windows, macOS и Linux. Проверяет новые версии через GitHub Releases, скачивает ZIP-архив под нужную платформу, распаковывает его и передаёт нативному коду для установки. Не требует сторонних сервисов, работает на чистом GitHub Releases.

## Возможности

- Проверка последней версии через GitHub Releases API
- Сравнение версий в формате semver (1.2.3) с нормализацией (убирается префикс `v` и суффикс `+build`)
- Скачивание одного ZIP-архива на платформу вместо сотен мелких файлов
- Отображение прогресса загрузки
- Полностью нативное применение обновления без внешних зависимостей
- Корректная распаковка `.app` на macOS с сохранением симлинков и прав
- Автоматическое снятие карантина при установке и обновлении на macOS
- Установочные файлы для конечного пользователя на каждой платформе: NSIS для Windows, DMG для macOS, `.run` и `.deb` для Linux, APK для Android
- Поддержка Android, Windows, macOS и Linux из одной кодовой базы

## Поддерживаемые платформы

| Платформа | Формат ZIP для автообновления | Способ применения обновления |
|-----------|-------------------------------|------------------------------|
| Android | `qnd_updater-<tag>-android.zip` | ZIP распаковывается, APK передаётся системному установщику |
| Windows | `qnd_updater-<tag>-windows.zip` | ZIP распаковывается в staging, helper `.bat` копирует файлы и перезапускает |
| macOS | `qnd_updater-<tag>-macos.zip` | ZIP распаковывается через `ditto`, helper `.sh` копирует `Contents` и перезапускает |
| Linux | `qnd_updater-<tag>-linux.zip` | ZIP распаковывается в staging, helper `.sh` копирует файлы и перезапускает |

Дополнительно в релиз кладутся установочные файлы для ручной установки: `.apk`, `-windows-setup.exe`, `.dmg`, `-linux-setup.run`, `.deb`, `.AppImage`.

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
  path_provider: ^2.1.5
```

Плагин использует `archive` для распаковки ZIP на Windows/Linux/Android, `http` для запросов к GitHub и `path_provider` для получения временной директории через `downloadLatest`. На macOS распаковка идёт через системный `ditto`, чтобы сохранить симлинки внутри `.app`.

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

Если используете установщик `-windows-setup.exe`, он по умолчанию ставит приложение в `C:\Program Files\qnd_updater_example`. В этом случае автообновление требует прав администратора: helper `.bat` попытается записать файлы в `Program Files`, получит `Access Denied` и обновление не применится. Есть два решения:

1. Устанавливать приложение в пользовательскую директорию, например `C:\Users\<user>\AppData\Local\qnd_updater`. Изменить путь по умолчанию можно в `installer.nsi`, строка `InstallDir`.
2. Запускать приложение от имени администратора. Это плохой UX, но для внутренних корпоративных приложений иногда приемлемо.

### macOS

> **УСТАНОВКА.** Скачайте DMG, откройте, кликните **правой кнопкой** по `Установить.command` - «Открыть» - подтвердите. Всё остальное скрипт сделает сам, включая снятие карантина. Автообновление потом работает без каких-либо действий с вашей стороны.

Четыре обязательных пункта для разработчика.

#### 1. Разрешение на сеть и отключённая песочница

macOS запускает приложения в песочнице только если она явно включена ключом `com.apple.security.app-sandbox`. Для автообновления песочница должна быть выключена, иначе приложение не сможет писать в свою же директорию в `/Applications`, и `applyUpdate` завершится ошибкой при попытке заменить бандл.

В Flutter-проектах по умолчанию песочница не включена, но её легко добавить случайно, например при копировании шаблона из другого проекта. Проверьте оба файла:

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

Если приложение запускается из `/Applications` и пытается себя обновить, ему нужны права на запись в `/Applications`. Если папка принадлежит другому пользователю (например, создана под root), `ditto` и `mv` в helper-скрипте упадут с `Permission denied`. В этом случае пользователь должен либо дать права на `/Applications/YourApp.app` для своей учётной записи, либо устанавливать приложение в `~/Applications`.

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

Внутри `.app` macOS лежат симлинки. Например, `App.framework/App` - это симлинк на `Versions/Current/App`, и таких симлинков в бандле десятки. Dart-пакет `archive` при распаковке пишет симлинки как обычные текстовые файлы, из-за чего FlutterEngine не находит `flutter_assets` и `icudtl.dat`, и приложение падает при запуске с ошибкой:

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
3. Появится диалог с предупреждением. Это стандартное предупреждение macOS для скриптов из интернета, оно появляется один раз. Нажмите «Открыть» ещё раз.
4. Скрипт сам скопирует приложение в `/Applications`, снимет карантин через `xattr -cr` и запустит приложение.
5. После этого приложение можно запускать двойным кликом как обычно. Все последующие автообновления проходят без участия пользователя, плагин снимает карантин с новой версии автоматически.

Если пользователь случайно перетащил `.app` из `.payload` в `/Applications` руками (продвинутые пользователи, которые включили показ скрытых файлов), и приложение не запускается, инструкция та же:

```bash
sudo xattr -cr /Applications/qnd_updater_example.app
```

или правой кнопкой по приложению, «Открыть», «Открыть».

Почему не просто «правый клик по .app»: если положить `.app` в корень DMG, пользователь сможет перетащить его в `/Applications` двойным кликом и получит предупреждение Gatekeeper при первом запуске. Скрытый `.payload` и скрипт убирают эту проблему, потому что пользователь физически не видит `.app` и не может сделать неправильно.

Чего это не решает:

- Приложение всё равно не будет нотаризовано. При первом запуске скрипта пользователь видит предупреждение macOS для `.command`-файла (одно нажатие «Открыть»).
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

#### Установка конечным пользователем

Релиз содержит три установочных формата для разных сценариев.

**`.run`-инсталлятор (рекомендуется для большинства).** Самый универсальный вариант. Работает на любом дистрибутиве, не требует root, спрашивает путь установки, создаёт `.desktop` для меню приложений и симлинк в `~/.local/bin`:

```bash
chmod +x qnd_updater-v0.0.2-linux-setup.run
./qnd_updater-v0.0.2-linux-setup.run
```

По умолчанию предлагает `~/.local/share/qnd_updater`. Можно указать свой путь. После установки приложение запускается из меню приложений или командой `qnd_updater`.

**`.deb` (для Debian, Ubuntu, Mint, Pop!_OS).**

```bash
sudo dpkg -i qnd-updater-0.0.2-linux.deb
sudo apt-get install -f   # если не хватает зависимостей
```

Устанавливается в `/usr/lib/qnd_updater/`, ярлык появляется в меню.

**AppImage (для любого дистрибутива без установки).**

```bash
chmod +x qnd_updater-v0.0.2-linux.AppImage
./qnd_updater-v0.0.2-linux.AppImage
```

AppImage не интегрируется в систему автоматически, но есть инструменты вроде `appimagelauncher`, которые это делают.

#### Автообновление на Linux

Автообновление работает **только для portable-раскладки**. Это значит, что приложение должно быть установлено в директорию, куда у процесса есть права на запись: `~/.local/share/qnd_updater/`, `~/Applications/`, домашний каталог, любая пользовательская папка.

Форматы установки и их совместимость с автообновлением:

| Формат | Автообновление |
|--------|----------------|
| `.run`-инсталлятор | Работает, если установлено в пользовательскую директорию (по умолчанию так и есть) |
| AppImage | Не работает. AppImage - это один файл, для обновления нужно перезаписать его целиком снаружи, плагин этого не делает |
| `.deb` | Не работает. `/usr/lib/` принадлежит root, процесс без прав не сможет перезаписать бинарник |
| portable ZIP | Работает. Распаковать в пользовательскую папку и запускать оттуда |

Почему автообновление не работает для системных установок:

1. Приложение установлено в `/usr/lib/qnd_updater/qnd_updater_example`, владелец root
2. Helper-скрипт запускается от имени пользователя (не root)
3. `cp` в helper падает с `Permission denied`
4. Приложение перезапускается, но со старой версией

Обходной путь для системных установок: запускать приложение с `sudo`. Это плохая практика и не рекомендуется. Если нужно обновляемое приложение, используйте `.run`-инсталлятор или portable ZIP.

#### Как `.run`-инсталлятор работает внутри

`.run` - это обычный shell-скрипт с встроенным `tar.gz`-архивом. Пользователь запускает его, скрипт:

1. Спрашивает путь установки (по умолчанию `~/.local/share/qnd_updater`)
2. Проверяет, существует ли директория, предлагает перезаписать
3. Распаковывает payload (`tail -n +<line> "$0" | tar -xz -C "$INSTALL_DIR"`)
4. Делает бинарник исполняемым
5. Создаёт `~/.local/share/applications/qnd-updater.desktop` с `Exec` на полный путь
6. Создаёт симлинк `~/.local/bin/qnd_updater` на бинарник
7. Выводит инструкцию

Разделитель payload: строка `__PAYLOAD_BELOW__` в конце скрипта. Собирается это всё в CI одной командой:

```bash
cat installer_header.sh payload.tar.gz > qnd_updater-v0.0.2-linux-setup.run
chmod +x qnd_updater-v0.0.2-linux-setup.run
```

Проверить содержимое `.run` без запуска:

```bash
# размер встроенного payload
ls -la qnd_updater-v0.0.2-linux-setup.run

# первые строки - header
head -50 qnd_updater-v0.0.2-linux-setup.run

# извлечь payload отдельно
PAYLOAD_LINE=$(awk '/^__PAYLOAD_BELOW__$/{print NR + 1; exit 0;}' qnd_updater-v0.0.2-linux-setup.run)
tail -n +$PAYLOAD_LINE qnd_updater-v0.0.2-linux-setup.run | tar -tzf -
```

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

### Установочные файлы для конечного пользователя

Помимо ZIP для автообновления, релиз **обязан** содержать установочные файлы для каждой платформы. Без них пользователь не сможет установить приложение в первый раз. ZIP-архивы для автообновления не годятся для первой установки: на macOS внутри архива лежит `.app`, который нельзя просто перетащить в `/Applications` без снятия карантина, на Windows нет ярлыков в меню Пуск, на Linux нет `.desktop` файла для интеграции в меню приложений.

Обязательный набор ассетов в релизе:

| Платформа | Установщик | Описание |
|-----------|------------|----------|
| Android | `qnd_updater-<tag>.apk` | Standalone APK, ставится через `adb install` или кликом на устройстве |
| Windows | `qnd_updater-<tag>-windows-setup.exe` | NSIS-инсталлятор с визардом, ярлыками, записью в «Установка и удаление программ» |
| macOS | `qnd_updater-<tag>-macos.dmg` | DMG с скриптом `Установить.command`, который копирует `.app` и снимает карантин |
| Linux | `qnd_updater-<tag>-linux-setup.run` | Самораспаковывающийся `.run`-скрипт, спрашивает путь, создаёт `.desktop` и симлинк в `~/.local/bin` |
| Linux | `qnd-updater-<version>-linux.deb` | DEB-пакет для Debian/Ubuntu |
| Linux | `qnd_updater-<tag>-linux.AppImage` | Portable AppImage для любого дистрибутива |

Вторая группа опциональна и нужна только для удобства:

- `qnd_updater-<tag>-windows.zip` - portable Windows
- `qnd_updater-<tag>-windows.exe` - одиночный EXE
- `qnd_updater-<tag>-linux.zip` - для автообновления
- `qnd_updater-<tag>-macos.zip` - для автообновления

Плагин использует только ZIP-архивы для автообновления. Все остальные файлы для пользователей, которые ставят приложение вручную.

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
- Windows: текущий процесс завершается, helper `.bat` ждёт выхода, копирует файлы, перезапускает приложение
- macOS: helper `.sh` ждёт выхода процесса, копирует `Contents` бандла, снимает карантин, перезапускает
- Linux: helper `.sh` через subshell ждёт выхода процесса, копирует файлы, перезапускает

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
| `downloadLatest({platformKey, onProgress})` | Обёртка над `downloadUpdate` с автоматическим выбором staging в `getTemporaryDirectory()` |

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

**Android.** Плагин ищет `.apk` в staging директории, получает URI через `FileProvider`, открывает системный установщик через `Intent.ACTION_VIEW`.

**Windows.** Плагин создаёт helper `.bat` в `%TEMP%`. Helper ждёт, пока процесс завершится (через `tasklist`), копирует файлы из staging в директорию приложения через `xcopy`, запускает приложение заново, удаляет себя.

**macOS.** Плагин создаёт helper `.sh`. Helper ждёт выхода процесса (через `kill -0`), копирует содержимое `Contents/` из staging `.app` в текущий бандл через `ditto`, снимает карантин, перезапускает приложение.

**Linux.** Плагин создаёт helper `.sh`, запускает его через `fork` и `setsid`, чтобы он жил после выхода процесса. Helper ждёт выхода (через `kill -0`), копирует файлы из staging в директорию приложения, запускает бинарник через subshell `( nohup "$EXE" & )`, удаляет себя. Subshell используется вместо `setsid`, потому что `setsid` отвязывает процесс от Wayland-сессии, и приложение не может подключиться к композитору.

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

Тег должен указывать на тот же коммит, что и ветка `main`. Если сделать тег от старого коммита, CI соберёт старую версию. Проверить:

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

### Обязательные требования к workflow

Любой workflow, который публикует релиз для `qnd_updater`, должен выполнять три вещи.

#### 1. Собирать ZIP-архивы для автообновления

Плагин ищет ассеты по фиксированному шаблону `qnd_updater-<tag>-<platform>.zip`. Если этого ассета нет, `checkForUpdate` вернёт «доступно обновление», но `downloadUpdate` не найдёт файл и вернёт `null`.

Обязательные шаги:

- Android: `flutter build apk --release`, упаковать APK в `qnd_updater-<tag>-android.zip`
- Windows: `flutter build windows --release`, упаковать `Release/*` в `qnd_updater-<tag>-windows.zip` через `Compress-Archive`
- macOS: собрать universal через `lipo`, подписать ad-hoc, упаковать через `ditto -c -k --rsrc --extattr`, чтобы сохранить симлинки
- Linux: `flutter build linux --release`, упаковать bundle в `qnd_updater-<tag>-linux.zip`

#### 2. Собирать установочные файлы

Без инсталляторов пользователь не сможет поставить приложение в первый раз.

**Windows - NSIS.** `choco install nsis -y`, затем `makensis installer.nsi`. NSIS не входит в образ `windows-2025-vs2026`, его нужно ставить явно. В скрипте ищем `makensis.exe` в `PATH`, `C:\Program Files (x86)\NSIS`, `C:\Program Files\NSIS`, `C:\ProgramData\chocolatey\bin`. Перед вызовом добавляем путь в `$env:GITHUB_PATH`, чтобы следующие шаги видели утилиту. При вызове `makensis` используем `MSYS_NO_PATHCONV=1` и `-DREF_NAME=` вместо `/DREF_NAME=`, иначе Git Bash превращает аргументы в пути Windows.

**macOS - DMG с установочным скриптом.** Приложение прячется в `.payload` (невидимая папка), рядом кладётся `Установить.command` и `ПРОЧТИ_МЕНЯ.txt`. Скрипт копирует `.app` в `/Applications` через `ditto`, снимает карантин через `xattr -cr`, запускает приложение.

**Linux - `.run`-инсталлятор.** Самораспаковывающийся shell-скрипт с встроенным `tar.gz`. Собирается командой `cat installer_header.sh payload.tar.gz > installer.run`.

#### 3. Публиковать релиз без `draft: true`

Плагин использует `GET /repos/{owner}/{repo}/releases/latest`, который **не возвращает черновики**. Если оставить `draft: true`, пользователи увидят `404 Not Found` и обновление не сработает.

```yaml
- uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}
    generate_release_notes: true
    # draft: true   <-- НЕ используйте
    files: |
      dist/*.zip
      dist/*.apk
      dist/*.exe
      dist/*.dmg
      dist/*.deb
      dist/*.AppImage
      dist/*.run
```

### Проверка обязательных ассетов перед публикацией

Добавьте в job `release` шаг перед публикацией:

```yaml
      - name: Check required assets
        run: |
          set -e
          REQUIRED=(
            "*.apk"
            "*-windows-setup.exe"
            "*-windows.zip"
            "*-macos.dmg"
            "*-macos.zip"
            "*-linux-setup.run"
            "*-linux.zip"
            "*-linux.deb"
          )
          MISSING=0
          for pattern in "${REQUIRED[@]}"; do
            if ! ls dist/$pattern >/dev/null 2>&1; then
              echo "::error::missing required asset: $pattern"
              MISSING=1
            fi
          done
          if [ "$MISSING" = "1" ]; then
            exit 1
          fi
          echo "all required assets present"
```

Если хотя бы одного установщика нет, job упадёт и релиз не опубликуется. Это защищает от ситуации, когда CI собрал все платформы, но забыл, например, DMG, и релиз ушёл без установщика macOS.

### Ключевые моменты workflow

- Universal macOS собирается через два прогона `flutter build macos` с разными `FLUTTER_XCODE_ARCHS` (arm64 и x86_64), затем `lipo` сливает бинарники всех фреймворков
- На macOS в CI не забудьте `flutter config --enable-native-assets` из-за `objective_c`
- Тег должен указывать на тот же коммит, что и ветка. Иначе CI соберёт старую версию
- Не используйте `draft: true` в `action-gh-release`, иначе плагин не увидит релиз через `/releases/latest`
- `ditto -c -k --rsrc --extattr` сохраняет xattr и симлинки при упаковке ZIP для macOS, обычный `zip` их ломает
- Для Windows NSIS вызывается с `MSYS_NO_PATHCONV=1` и `-DREF_NAME=`, иначе Git Bash превращает `/DREF_NAME=v0.0.1` в путь Windows

## Ограничения

**Android.** Тихая установка без диалога невозможна. Система требует подтверждения пользователя. Публикация в Google Play не позволяет обновлять APK через сторонние источники, ограничение действует на уровне политики магазина.

**macOS.** Песочница (app sandbox) должна быть выключена, иначе приложение не сможет заменить свой же бандл при автообновлении. Приложение должно быть собрано с entitlements `com.apple.security.network.client`, без него сеть недоступна. DMG содержит установочный скрипт `Установить.command`, который копирует приложение и снимает карантин. Все последующие автообновления проходят без участия пользователя, потому что `applyUpdate` снимает карантин с новой версии автоматически. Полностью убрать предупреждение Gatekeeper можно только через Apple Developer ID и нотаризацию.

**Windows.** Приложение должно иметь право записи в свою директорию. Не устанавливайте в `C:\Program Files`, если не готовы запускать с правами администратора.

**Linux.** Обновление работает только для portable-раскладки. Если приложение установлено через `.deb` в `/usr/lib`, у процесса нет прав на запись. AppImage обновлять тоже нетривиально, нужен отдельный подход.

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

Если повторяется при каждом обновлении, распаковка снова идёт через `ZipDecoder`, а не через `ditto`.

### macOS: приложение повреждено после установки из DMG

Gatekeeper. Откройте DMG и запустите `Установить.command` через правый клик, «Открыть». Скрипт сам снимет карантин. Если хотите сделать вручную:

```bash
sudo xattr -cr /Applications/YourApp.app
```

### Linux: приложение закрылось и не открылось после обновления

Проверьте лог helper-скрипта:

```bash
ls -t /tmp/qnd_updater_apply_*.log | head -1
cat $(ls -t /tmp/qnd_updater_apply_*.log | head -1)
```

Ищите:

- `staging version:` и `install version:` - должны совпадать. Если расходятся, копирование не сработало
- `new pid: N` - процесс запущен
- `helper done` - скрипт завершился без ошибок

Если в логе `new pid` есть, а процесса нет - приложение упало при запуске. Проверьте:

```bash
ps aux | grep qnd_updater_example | grep -v grep
journalctl --user -n 50 | grep -i qnd_updater
```

Если версия в файле `~/qnd_test/version` старая, значит `cp` не сработал. Проверьте права на директорию:

```bash
ls -la ~/qnd_test/
```

### Linux: приложение установлено в /usr/lib, автообновление не работает

`/usr/lib/` принадлежит root. Helper-скрипт запускается от имени пользователя и не может перезаписать файлы. Используйте `.run`-инсталлятор или portable ZIP, которые ставят приложение в пользовательскую директорию.

### APK not found на Android

Проверьте имя ассета в релизе. Плагин ищет `qnd_updater-<tag>-android.zip`. Внутри архива должен быть `qnd_updater.apk`.

### Keystore not found при сборке

Если используете `rootProject.file(it)` в `build.gradle.kts`, в `key.properties` должно быть `storeFile=upload-keystore.jks` без префикса `../`, а сам keystore лежать в `android/upload-keystore.jks`.

Если используете `file(it)`, в `key.properties` должно быть `storeFile=../upload-keystore.jks`, keystore в `android/upload-keystore.jks`.

### type '_Uint8ArrayView' is not a subtype of type 'Stream<List<int>>'

Старый код распаковки. Обновите `UpdaterService.downloadUpdate`, используется `writeAsBytes(file.content as List<int>)` вместо каста к Stream.

### Windows: makensis not found

NSIS не входит в образ `windows-2025-vs2026`. Добавьте шаг `choco install nsis -y --no-progress` и добавьте путь в `$env:GITHUB_PATH`. Готовый пример в `.github/workflows/Release.yml`.

### Windows: Can't open script "C:/Program Files/Git/DREF_NAME=..."

Git Bash на Windows превращает аргументы, начинающиеся с `/`, в пути. Передавайте переменные NSIS через `-D` вместо `/D` и выставляйте `MSYS_NO_PATHCONV=1`:

```bash
MSYS_NO_PATHCONV=1 makensis -V2 -DREF_NAME="$TAG" -DVERSION="$VERSION" installer.nsi
```

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