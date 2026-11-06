import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_services.dart';
import 'core/ui/glass.dart';
import 'features/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Barra de sistema transparente para que el fondo glass llegue al borde.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  await initializeDateFormatting('es');
  await services.init();
  runApp(const ProCamApp());
}

class ProCamApp extends StatelessWidget {
  const ProCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GEO CUSCA SUR',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Si el usuario tiene la letra del sistema muy grande, se limita para
      // que botones y tarjetas no se desborden en ninguna pantalla.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15)),
          child: child!,
        );
      },
      home: const HomeShell(),
    );
  }
}
