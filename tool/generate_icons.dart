// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Multi-resolution ICO builder for Windows.
Uint8List buildMultiResIco(List<img.Image> images) {
  final header = ByteData(6);
  header.setUint16(0, 0, Endian.little); // Reserved, must be 0
  header.setUint16(2, 1, Endian.little); // 1 = ICO
  header.setUint16(4, images.length, Endian.little); // Number of images

  final entries = <ByteData>[];
  final encodedPngs = <Uint8List>[];

  int currentOffset = 6 + (images.length * 16);

  for (final image in images) {
    final pngBytes = Uint8List.fromList(img.encodePng(image));
    encodedPngs.add(pngBytes);

    final entry = ByteData(16);
    entry.setUint8(0, image.width >= 256 ? 0 : image.width);
    entry.setUint8(1, image.height >= 256 ? 0 : image.height);
    entry.setUint8(2, 0); // Palette color count
    entry.setUint8(3, 0); // Reserved
    entry.setUint16(4, 1, Endian.little); // Color planes
    entry.setUint16(6, 32, Endian.little); // Bits per pixel
    entry.setUint32(8, pngBytes.length, Endian.little);
    entry.setUint32(12, currentOffset, Endian.little);

    entries.add(entry);
    currentOffset += pngBytes.length;
  }

  final builder = BytesBuilder();
  builder.add(header.buffer.asUint8List());
  for (final entry in entries) {
    builder.add(entry.buffer.asUint8List());
  }
  for (final png in encodedPngs) {
    builder.add(png);
  }

  return builder.toBytes();
}

/// Generates a centered foreground image on a transparent canvas of targetSize x targetSize,
/// where the source logo occupies [contentScale] of the canvas size.
img.Image makeAdaptiveForeground(
  img.Image source,
  int canvasSize,
  double contentScale,
) {
  final result = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  // canvas initialized to transparent (0, 0, 0, 0)

  final targetContentSize = (canvasSize * contentScale).round();
  final resizedLogo = img.copyResize(
    source,
    width: targetContentSize,
    height: targetContentSize,
    interpolation: img.Interpolation.cubic,
  );

  final startX = (canvasSize - targetContentSize) ~/ 2;
  final startY = (canvasSize - targetContentSize) ~/ 2;

  img.compositeImage(result, resizedLogo, dstX: startX, dstY: startY);
  return result;
}

void main() {
  print('--- Starting Daria Icon Generation ---');

  final sourceFile = File('assets/images/icons/dariaicon.png');
  if (!sourceFile.existsSync()) {
    print('ERROR: Source file ${sourceFile.path} does not exist!');
    exit(1);
  }

  final sourceBytes = sourceFile.readAsBytesSync();
  final sourceImage = img.decodeImage(sourceBytes);
  if (sourceImage == null) {
    print('ERROR: Failed to decode ${sourceFile.path}!');
    exit(1);
  }
  print('Source logo decoded: ${sourceImage.width}x${sourceImage.height}');

  // 1. Android Standard Mipmap Icons (ic_launcher.png)
  final androidMipmaps = <String, int>{
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (final entry in androidMipmaps.entries) {
    final folder = Directory('android/app/src/main/res/${entry.key}');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    final size = entry.value;
    final resized = img.copyResize(
      sourceImage,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    final targetPath = '${folder.path}/ic_launcher.png';
    File(targetPath).writeAsBytesSync(img.encodePng(resized));
    print('Generated Android launcher: $targetPath ($size x $size)');
  }

  // 2. Android Adaptive Icons (ic_launcher_foreground.png)
  // Adaptive icons have 108dp size: mdpi=108, hdpi=162, xhdpi=216, xxhdpi=324, xxxhdpi=432
  // Safe zone is 72dp (~66.7% scale). Using ~68% ensures the squircle card fits safely.
  final adaptiveSizes = <String, int>{
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
  };

  for (final entry in adaptiveSizes.entries) {
    final folder = Directory('android/app/src/main/res/${entry.key}');
    final size = entry.value;
    final foreground = makeAdaptiveForeground(sourceImage, size, 0.68);
    final targetPath = '${folder.path}/ic_launcher_foreground.png';
    File(targetPath).writeAsBytesSync(img.encodePng(foreground));
    print('Generated Android adaptive foreground: $targetPath ($size x $size)');
  }

  // Ensure mipmap-anydpi-v26/ic_launcher.xml exists
  final anyDpiFolder = Directory('android/app/src/main/res/mipmap-anydpi-v26');
  if (!anyDpiFolder.existsSync()) {
    anyDpiFolder.createSync(recursive: true);
  }
  final adaptiveXml = File('${anyDpiFolder.path}/ic_launcher.xml');
  adaptiveXml.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  print('Generated ${adaptiveXml.path}');

  // Ensure colors.xml has ic_launcher_background
  final valuesFolder = Directory('android/app/src/main/res/values');
  if (!valuesFolder.existsSync()) {
    valuesFolder.createSync(recursive: true);
  }
  final colorsFile = File('${valuesFolder.path}/colors.xml');
  if (colorsFile.existsSync()) {
    final existing = colorsFile.readAsStringSync();
    if (!existing.contains('ic_launcher_background')) {
      colorsFile.writeAsStringSync(
        existing.replaceFirst(
          '</resources>',
          '    <color name="ic_launcher_background">#121212</color>\n</resources>',
        ),
      );
    }
  } else {
    colorsFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#121212</color>
</resources>
''');
  }
  print('Ensured colors.xml with ic_launcher_background (#121212)');

  // 3. Windows Multi-Resolution ICO
  final icoSizes = [16, 24, 32, 48, 64, 128, 256];
  final icoImages = <img.Image>[];
  for (final size in icoSizes) {
    icoImages.add(
      img.copyResize(
        sourceImage,
        width: size,
        height: size,
        interpolation: img.Interpolation.cubic,
      ),
    );
  }
  final icoBytes = buildMultiResIco(icoImages);
  const windowsIcoPath = 'windows/runner/resources/app_icon.ico';
  File(windowsIcoPath).writeAsBytesSync(icoBytes);
  print(
    'Generated Windows multi-res ICO: $windowsIcoPath (${icoBytes.length} bytes, ${icoSizes.length} resolutions)',
  );

  print('--- All Icons Successfully Generated ---');
}
