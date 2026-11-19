import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/editor_home.dart';
import 'services/app_settings.dart';

class FlowMdApp extends StatefulWidget {
  const FlowMdApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<FlowMdApp> createState() => _FlowMdAppState();
}

class _FlowMdAppState extends State<FlowMdApp> {
  late final AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings(widget.prefs);
    _settings.themeMode.addListener(_onSettingsChanged);
    _settings.fontSize.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.themeMode.removeListener(_onSettingsChanged);
    _settings.fontSize.removeListener(_onSettingsChanged);
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _settings.fontSize.value;
    return MaterialApp(
      title: 'Flow MD Editor',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(fontSize),
      darkTheme: _buildDarkTheme(fontSize),
      themeMode: _settings.themeMode.value,
      home: EditorHome(settings: _settings),
    );
  }
}

const _accent = Color(0xFF0A84FF);

ThemeData _buildLightTheme(double fontSize) {
  const scaffold = Color(0xFFF5F5F7);
  const surface = Color(0xFFFFFFFF);
  const border = Color(0xFFD2D2D7);
  final base = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.light,
      surface: surface,
    ),
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    dividerColor: border,
    cardColor: surface,
    useMaterial3: true,
  );
  return base.copyWith(
    dialogTheme: const DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Color(0xFF007AFF),
      selectionColor: Color(0xFFB3D7FF),
      selectionHandleColor: Color(0xFF007AFF),
    ),
    segmentedButtonTheme: _segmentedTheme(
      background: const Color(0xFFE8E8ED),
      selected: const Color(0xFFFFFFFF),
      selectedFg: const Color(0xFF1C1C1E),
      fg: const Color(0xFF6C6C70),
      side: border,
    ),
    textTheme: base.textTheme
        .apply(
          bodyColor: const Color(0xFF1C1C1E),
          displayColor: const Color(0xFF1C1C1E),
        )
        .copyWith(
          bodyMedium: TextStyle(
            fontSize: fontSize,
            height: 1.5,
            color: const Color(0xFF1C1C1E),
          ),
          bodyLarge: TextStyle(
            fontSize: fontSize,
            height: 1.5,
            color: const Color(0xFF1C1C1E),
          ),
        ),
  );
}

ThemeData _buildDarkTheme(double fontSize) {
  const scaffold = Color(0xFF1C1C1E);
  const surface = Color(0xFF2C2C2E);
  const border = Color(0xFF3A3A3C);
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
      surface: surface,
    ),
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    dividerColor: border,
    cardColor: surface,
    useMaterial3: true,
  );
  return base.copyWith(
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Color(0xFF0A84FF),
      selectionColor: Color(0xFF3F638B),
      selectionHandleColor: Color(0xFF0A84FF),
    ),
    segmentedButtonTheme: _segmentedTheme(
      background: const Color(0xFF2C2C2E),
      selected: const Color(0xFF48484A),
      selectedFg: Colors.white,
      fg: const Color(0xFFAEAEB2),
      side: const Color(0xFF48484A),
    ),
    textTheme: ThemeData.dark().textTheme
        .apply(
          bodyColor: const Color(0xFFE5E5EA),
          displayColor: const Color(0xFFF2F2F7),
        )
        .copyWith(
          bodyMedium: TextStyle(
            fontSize: fontSize,
            height: 1.5,
            color: const Color(0xFFE5E5EA),
          ),
          bodyLarge: TextStyle(
            fontSize: fontSize,
            height: 1.5,
            color: const Color(0xFFE5E5EA),
          ),
        ),
  );
}

SegmentedButtonThemeData _segmentedTheme({
  required Color background,
  required Color selected,
  required Color selectedFg,
  required Color fg,
  required Color side,
}) {
  return SegmentedButtonThemeData(
    style: ButtonStyle(
      visualDensity: VisualDensity.compact,
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return selected;
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return selectedFg;
        return fg;
      }),
      side: WidgetStatePropertyAll(BorderSide(color: side)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
