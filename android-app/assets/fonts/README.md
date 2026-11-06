# Using your own font

1. Copy your font file here, e.g. `assets/fonts/MyFont.ttf`.
2. In `pubspec.yaml`, under `flutter:` add:

       fonts:
         - family: MyFont
           fonts:
             - asset: assets/fonts/MyFont.ttf

3. In `lib/theme.dart` set `static const String? custom = 'MyFont';`

By default the app uses Orbitron (headings) and Rajdhani (text) from Google
Fonts, which are downloaded the first time and need an internet connection
once. A bundled font works fully offline.
