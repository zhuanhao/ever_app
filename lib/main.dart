import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'services/api_client.dart';
import 'services/sse_service.dart';
import 'widgets/side_drawer.dart';

void main() {
  runApp(const EverApp());
}

class EverApp extends StatelessWidget {
  const EverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '珩心',
      theme: _buildTheme(),
      home: const HomeShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

ThemeData _buildTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8E7CC3),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFFAF8F5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFAF8F5),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF3B3B3B),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ApiClient _api = ApiClient();
  late final SseService _sse = SseService(_api);

  @override
  void initState() {
    super.initState();
    _sse.start();
  }

  @override
  void dispose() {
    _sse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideDrawer(),
      body: const ChatScreen(),
    );
  }
}
