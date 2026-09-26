# qnd_updater

Flutter плагин для обновления приложений на Android, Windows, macOS и Linux. Проверяет новые версии через GitHub Releases, скачивает ZIP-архив под нужную платформу, распаковывает его и передаёт нативному коду для установки. Не требует сторонних сервисов, работает на чистом GitHub Releases.

## Возможности

- Проверка последней версии через GitHub Releases API
- Сравнение версий в формате semver (1.2.3) с нормализацией (убирается префикс v и суффикс +build)
- Скачивание одного ZIP-архива на платформу вместо сотен мелких файлов
- Отображение прогресса загрузки
- Полностью нативное применение обновления без внешних зависимостей
- Поддержка Android, Windows, macOS и Linux из одной кодовой базы

## Поддерживаемые платформы

| Платформа | Формат ассета | Способ установки |
|-----------|---------------|------------------|
| Android | `qnd_updater-<tag>-android.zip` | ZIP распаковывается, APK передаётся системному установщику |
| Windows | `qnd_updater-<tag>-windows.zip` | ZIP распаковывается в staging, helper .bat копирует файлы и перезапускает |
| macOS | `qnd_updater-<tag>-macos.zip` | ZIP распаковывается в staging, helper .sh копирует Contents и перезапускает |
| Linux | `qnd_updater-<tag>-linux.zip` | ZIP распаковывается в staging, helper .sh копирует файлы и перезапускает |

Дополнительно в релиз можно положить файлы для ручной установки: `.apk`, `.exe`, `.dmg`, `.AppImage`, `.deb`.

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
  archive: ^3.6.1
  http: ^1.6.0
```

Плагин использует пакет `archive` для распаковки ZIP и `http` для запросов к GitHub.

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

Если хотите использовать `../upload-keystore.jks` (файл в родительской директории), замените в build.gradle `rootProject.file(...)` на `file(...)` и положите keystore в `android/app/`.

### Windows

Ничего специально настраивать не нужно. Windows не использует песочницу для desktop-приложений, исходящие сетевые соединения разрешены по умолчанию.

Приложение должно иметь право записи в свою директорию. Не устанавливайте в `C:\Program Files`, если не готовы запускать с правами администратора. Тестируйте обновление из пользовательской папки, например `C:\Users\<user>\qnd_test\`.

### macOS

Есть три обязательных пункта.

#### 1. Разрешение на сеть

macOS запускает приложения в песочнице. Без явного разрешения все запросы к `api.github.com` падают с `SocketException`. Добавьте ключ в оба файла entitlements.

`macos/Runner/DebugProfile.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
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
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Проверить, что ключ попал в собранный бандл:

```bash
codesign -d --entitlements :- /path/to/Your.app | grep network
```

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

#### 3. Снятие карантина после установки

Если пользователь скачал `.dmg` через браузер, macOS помечает приложение атрибутом `com.apple.quarantine` и отказывается запускать:

```
Приложение повреждено, и его не удается открыть.
Переместите приложение в Корзину.
```

Это не повреждение, а Gatekeeper. Снять карантин:

```bash
sudo xattr -cr /Applications/YourApp.app
```

Или открыть через контекстное меню: правой кнопкой по `.app`, выбрать «Открыть», подтвердить в диалоге. После этого macOS запомнит выбор, и приложение будет запускаться обычным двойным кликом.

Полностью убрать это предупреждение можно только через подпись сертификатом Apple Developer и нотаризацию, что требует платного аккаунта.

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

Для ручной установки можно дополнительно положить:

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
- Windows: текущий процесс завершается, helper .bat ждёт выхода, копирует файлы, перезапускает приложение
- macOS: helper .sh ждёт выхода процесса, копирует Contents бандла, снимает quarantine, перезапускает
- Linux: helper .sh через fork и setsid ждёт выхода процесса, копирует файлы, перезапускает

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

`platformKey` принимает значения `android`, `windows`, `macos`, `linux`.

`onProgress` вызывается при скачивании с текущим и общим количеством байт.

### UpdateResult

Результат скачивания:

- `version`: версия без префикса v
- `tag`: тег релиза как есть
- `stagingDir`: директория с распакованными файлами
- `totalBytes`: сколько байт скачано

## Как это работает

### Проверка обновления

1. Плагин получает версию приложения через нативный метод `getAppVersion`
2. Запрашивает последний релиз через `GET /repos/{owner}/{repo}/releases/latest`
3. Нормализует обе версии: убирает префикс v и суффикс +build
4. Сравнивает числа major.minor.patch

Черновики (draft) релизов через `/releases/latest` не возвращаются. Если видите 404, проверьте, опубликован ли релиз.

### Скачивание обновления

1. Плагин формирует имя ассета `qnd_updater-<tag>-<platform>.zip`
2. Ищет его в списке ассетов последнего релиза
3. Скачивает с прогрессом в staging директорию
4. Распаковывает ZIP
5. Удаляет временный ZIP
6. Возвращает `UpdateResult`

### Применение обновления

Поведение зависит от платформы.

**Android.** Плагин ищет `.apk` в staging директории, получает URI через `FileProvider`, открывает системный установщик через `Intent.ACTION_VIEW`.

**Windows.** Плагин создаёт helper `.bat` в `%TEMP%`. Helper ждёт, пока процесс завершится (через `tasklist`), копирует файлы из staging в директорию приложения через `xcopy`, запускает приложение заново, удаляет себя.

**macOS.** Плагин создаёт helper `.sh`. Helper ждёт выхода процесса (через `kill -0`), копирует содержимое `Contents/` из staging `.app` в текущий бандл через `ditto`, снимает quarantine, перезапускает приложение.

**Linux.** Плагин создаёт helper `.sh`, запускает его через `fork` и `setsid`, чтобы он жил после выхода процесса. Helper ждёт выхода (через `kill -0`), копирует файлы из staging в директорию приложения, запускает бинарник через `nohup`, удаляет себя.

## GitHub Actions

Пример workflow, который собирает все четыре платформы и публикует релиз. Полный файл смотрите в репозитории, здесь только скелет:

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

env:
  FLUTTER_VERSION: '3.47.5'

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - name: Build
        working-directory: example
        run: |
          flutter pub get
          flutter build apk --release

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - name: Build
        working-directory: example
        run: |
          flutter config --enable-windows-desktop
          flutter pub get
          flutter build windows --release

  build-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            clang cmake ninja-build pkg-config \
            libgtk-3-dev liblzma-dev libstdc++-12-dev \
            libglu1-mesa
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - name: Build
        working-directory: example
        run: |
          flutter config --enable-linux-desktop
          flutter pub get
          flutter build linux --release

  build-macos:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - name: Build
        working-directory: example
        run: |
          flutter config --enable-macos-desktop
          flutter pub get
          flutter build macos --release

  release:
    needs: [build-android, build-windows, build-linux, build-macos]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          path: dist
          merge-multiple: true
      - uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref_name }}
          generate_release_notes: true
          files: dist/*.zip
```

Важные моменты:

- Universal macOS собирается через два прогона `flutter build macos` с разными `FLUTTER_XCODE_ARCHS` (arm64 и x86_64), затем `lipo` сливает бинарники
- На macOS в CI не забудьте `flutter config --enable-native-assets` из-за `objective_c`
- Тег должен указывать на тот же коммит, что и ветка. Иначе CI соберёт старую версию
- Не используйте `draft: true` в `action-gh-release`, иначе плагин не увидит релиз через `/releases/latest`

## Ограничения

**Android.** Тихая установка без диалога невозможна. Система требует подтверждения пользователя. Публикация в Google Play не позволяет обновлять APK через сторонние источники, ограничение действует на уровне политики магазина.

**macOS.** Приложение должно быть собрано с entitlements `com.apple.security.network.client`. Без этого сеть недоступна. Скачанный `.dmg` требует снятия карантина через `xattr` или через контекстное меню. Полностью убрать предупреждение можно только через Apple Developer ID и нотаризацию.

**Windows.** Приложение должно иметь право записи в свою директорию. Не устанавливайте в `C:\Program Files`, если не готовы запускать с правами администратора.

**Linux.** Обновление работает только для portable-раскладки. Если приложение установлено через `.deb` в `/usr/lib`, у процесса нет прав на запись. AppImage обновлять тоже нетривиально, нужен отдельный подход.

**Общее.** GitHub Release не подходит для очень большого числа ассетов. Если планируете сотни файлов, используйте собственный CDN. Для ZIP-подхода это не критично, но имейте в виду.

## Диагностика

### GitHub вернул 404

Скорее всего релиз в статусе draft. Откройте GitHub Releases и опубликуйте его. `/releases/latest` не возвращает черновики.

### SocketException на macOS

Не добавлен ключ `com.apple.security.network.client` в entitlements. Проверьте оба файла, `DebugProfile.entitlements` и `Release.entitlements`.

### Couldn't resolve native function 'DOBJC_initializeApi'

Проблема с `path_provider_foundation 2.6.0` на macOS. Добавьте в `pubspec.yaml`:

```yaml
dependency_overrides:
  path_provider_foundation: 2.5.1
```

### Приложение на macOS повреждено

Gatekeeper. Снять карантин:

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