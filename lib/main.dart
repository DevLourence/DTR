import 'dart:io';
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:path/path.dart' as p;
import 'pages/landing_page.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    
    // Explicitly load sqlite3.dll for Windows to avoid 'Couldn't resolve native function' errors
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () {
        try {
          // Try to find the bundled sqlite3.dll in the same directory as the executable
          final libraryPath = p.join(p.dirname(Platform.resolvedExecutable), 'sqlite3.dll');
          if (File(libraryPath).existsSync()) {
            return DynamicLibrary.open(libraryPath);
          }
        } catch (_) {
          // Fallback to default lookup if explicit path fails
        }
        return DynamicLibrary.open('sqlite3.dll');
      });
    }
    
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const DtrApp());
}

class DtrApp extends StatelessWidget {
  const DtrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DTR FORM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0038A8),
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      home: const LandingPage(),
    );
  }
}
