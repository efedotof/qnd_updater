# qnd_updater

Flutter плагин для инкрементального обновления приложений на Android, Windows и macOS. Проверяет новые версии через GitHub Releases, скачивает только изменённые файлы и применяет обновление без сторонних библиотек.

## Возможности

- Проверка последней версии через GitHub Releases API
- Сравнение версий в формате semver (1.2.3)
- Инкрементальное обновление для Windows и macOS: скачиваются только изменённые файлы, а не весь архив целиком
- Полное обновление APK для Android с передачей в системный установщик
- Проверка целостности каждого файла через SHA-256
- Отображение прогресса загрузки
- Полностью нативное применение обновления без внешних зависимостей

## Поддерживаемые платформы

| Платформа | Метод обновления |
|-----------|------------------|
| Android | Скачивание APK и установка через системный установщик |
| Windows | Пофайловое обновление из staging директории |
| macOS | Пофайловое обновление из staging директории |

## Установка

Добавьте плагин в `pubspec.yaml`:

```yaml
dependencies:
  qnd_updater:
    git:
      url: https://github.com/efedotof/qnd_updater.git
      ref: main
```

Или через путь, если плагин локальный:

```yaml
dependencies:
  qnd_updater:
    path: ../qnd_updater
```

## Настройка для Android

### 1. Разрешение на установку APK

Добавьте разрешение в `android/app/src/main/AndroidManifest.xml` вашего приложения:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
<uses-permission android:name="android.permission.INTERNET" />
```

### 2. Регистрация FileProvider

В том же манифесте, внутри тега `<application>`, добавьте провайдер:

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

### 3. Файл с путями

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

### 4. Подпись приложения

Для обновления через плагин приложение должно быть подписано release ключом, а не debug. Настройте `android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

Файл `android/key.properties` (не добавляйте в git):

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=../upload-keystore.jks
```

## Структура релиза на GitHub

Плагин ожидает, что в GitHub Release прикреплены следующие ассеты:

- `manifest-windows.json` с описанием файлов Windows сборки
- `manifest-macos.json` с описанием файлов macOS сборки
- `qnd_updater-vX.Y.Z.apk` для Android
- `qnd_updater-vX.Y.Z-macos-universal.zip` с universal сборкой macOS
- По одному ассету на каждый файл для Windows и macOS (для инкрементального обновления)

Формат манифеста:

```json
{
  "version": "1.2.3",
  "files": [
    {
      "path": "data/flutter_assets/AssetManifest.json",
      "sha256": "abcdef...",
      "size": 1234,
      "asset": "windows__data%2Fflutter_assets%2FAssetManifest.json"
    }
  ]
}
```

Поле `asset` содержит имя соответствующего файла в GitHub Release. Слэши в имени закодированы через URL encoding, так как GitHub не принимает слеши в именах ассетов.

## Использование

### Проверка наличия обновления

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

Если репозиторий приватный, передайте GitHub токен в `githubToken`.

### Обновление для Windows и macOS

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:qnd_updater/qnd_updater.dart';

final platformKey = Platform.isWindows ? 'windows' : 'macos';
final appDir = File(Platform.resolvedExecutable).parent;

final service = UpdaterService(
  owner: 'your-org',
  repo: 'your-repo',
);

final plan = await service.planUpdate(
  appDir: appDir,
  platformKey: platformKey,
);

if (plan == null || plan.changed.isEmpty) {
  print('Все файлы актуальны');
  return;
}

final release = await service.fetchLatestRelease();
final tempDir = await getTemporaryDirectory();
final staging = Directory('${tempDir.path}/qnd_staging');

await service.downloadChanged(
  plan: plan,
  release: release!,
  stagingDir: staging,
  onProgress: (done, total) {
    final percent = total > 0 ? (done * 100 / total).toStringAsFixed(1) : '0';
    print('Загружено $percent%');
  },
);

await updater.applyUpdate(staging.path);
exit(0);
```

После вызова `applyUpdate` текущий процесс завершается через `exit(0)`. Нативный код плагина запускает helper скрипт, который дожидается завершения процесса, копирует файлы и перезапускает приложение.

### Обновление для Android

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:qnd_updater/qnd_updater.dart';

final service = UpdaterService(owner: 'your-org', repo: 'your-repo');
final release = await service.fetchLatestRelease();
final apkAsset = release!.assets['qnd_updater-${release.tag}.apk'];

if (apkAsset == null) {
  print('APK не найден в релизе');
  return;
}

final tempDir = await getTemporaryDirectory();
final apkFile = File('${tempDir.path}/update.apk');

final client = HttpClient();
final request = await client.getUrl(Uri.parse(apkAsset.browserDownloadUrl));
final response = await request.close();
final sink = apkFile.openWrite();
await response.pipe(sink);
await sink.close();
client.close();

await updater.applyUpdate(apkFile.path);
```

Плагин открывает системный установщик через `Intent.ACTION_VIEW` с `FileProvider`. Пользователь подтверждает установку вручную.

## API

### QndUpdater

Основной класс плагина.

| Метод | Описание |
|-------|----------|
| `getAppVersion()` | Возвращает текущую версию приложения |
| `checkForUpdate({githubToken, owner, repo})` | Проверяет наличие новой версии через GitHub |
| `applyUpdate(String path)` | Применяет обновление из staging директории (Windows, macOS) или устанавливает APK (Android) |

### UpdateStatus

Результат проверки обновления.

- `upToDate` текущая версия актуальна
- `updateAvailable` доступна новая версия
- `error` ошибка при проверке

### UpdaterService

Сервис для работы с GitHub Releases и инкрементального обновления.

| Метод | Описание |
|-------|----------|
| `fetchLatestRelease()` | Возвращает информацию о последнем релизе |
| `planUpdate({appDir, platformKey})` | Строит план обновления: какие файлы изменились |
| `downloadChanged({plan, release, stagingDir, onProgress})` | Скачивает изменённые файлы в staging директорию |

## Как это работает

### Проверка обновления

1. Плагин получает текущую версию приложения через нативный метод `getAppVersion`
2. Запрашивает последний релиз через `GET /repos/{owner}/{repo}/releases/latest`
3. Сравнивает версии по частям (major.minor.patch)

### Инкрементальное обновление для Windows и macOS

1. Скачивается `manifest-{platform}.json` из релиза
2. Для каждого файла из манифеста вычисляется SHA-256 и сравнивается с локальным
3. Скачиваются только те файлы, которые отсутствуют или изменились
4. Скачанные файлы помещаются в staging директорию с сохранением структуры
5. После завершения загрузки вызывается нативный `applyUpdate`
6. Нативный код запускает helper скрипт, который:
   - ожидает завершения текущего процесса
   - копирует файлы из staging в директорию приложения
   - перезапускает приложение
   - удаляет helper скрипт

### Обновление для Android

1. Скачивается полный APK из релиза
2. APK передаётся системному установщику через `FileProvider`
3. Пользователь подтверждает установку

## GitHub Actions

Пример workflow для автоматической сборки релиза:

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            platform: android
          - os: windows-latest
            platform: windows
          - os: macos-14
            platform: macos
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: stable
      - name: Build
        working-directory: example
        run: |
          flutter pub get
          flutter build ${{ matrix.platform }} --release
```

Полный пример workflow со сборкой universal macOS и генерацией манифестов смотрите в репозитории.

## Ограничения

- Android: тихое обновление невозможно, требуется подтверждение пользователя. Публикация в Google Play не позволяет обновлять APK через сторонние источники, ограничение действует на уровне политики магазина.
- macOS: если приложение подписано сертификатом Apple, замена файлов сломает подпись. Для корректной работы требуется переподпись после обновления или использование механизмов нотаризации.
- Windows: приложение должно иметь права записи в свою директорию. При установке в Program Files нужны права администратора.
- GitHub Release плохо подходит для большого числа мелких файлов. При сотнях ассетов загрузка может стать медленной, лучше использовать собственный CDN.

