import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Respaldo completo de la app en un solo archivo .zip:
///  - base de datos (inspecciones, tramos, fotos, visitas)
///  - fotos de evidencia, firmas y logotipo
///  - ajustes (institución, inspector, plantilla de marca de agua…)
///
/// Sirve para cambiar de teléfono o reinstalar sin perder nada. El archivo
/// se comparte (Drive, WhatsApp, correo, USB) y se restaura desde Ajustes.
class BackupService {
  static const _prefsKeys = [
    'institution', 'department', 'inspectorName', 'inspectorRole',
    'compactShare', 'askActivity', 'recentActivities', 'watermarkConfig', 'logoPath',
  ];

  /// Crea el respaldo y devuelve el archivo .zip.
  Future<File> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final out = File(p.join(tmp.path, 'GEO-CUSCA-SUR_respaldo_$stamp.zip'));
    if (await out.exists()) await out.delete();

    // Copia consistente de la base de datos (cerrada mientras se copia).
    final dbPath = await AppDatabase.filePath();
    final dbCopy = File(p.join(tmp.path, 'geomark.db'));
    await AppDatabase.instance.close();
    await File(dbPath).copy(dbCopy.path);

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, Object?>{for (final k in _prefsKeys) k: prefs.get(k)};
    final manifest = File(p.join(tmp.path, 'manifest.json'));
    await manifest.writeAsString(jsonEncode({
      'app': 'GEO CUSCA SUR',
      'format': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'docsPath': docs.path,
      'prefs': prefsMap,
    }));

    // ZipFileEncoder escribe directo al disco (no carga todas las fotos en
    // memoria). Llamadas dinámicas: compatibles con archive 3.x y 4.x.
    final dynamic enc = ZipFileEncoder();
    enc.create(out.path);
    Future<void> add(File f, String name) async {
      final r = enc.addFile(f, name);
      if (r is Future) await r;
    }

    await add(manifest, 'manifest.json');
    await add(dbCopy, 'geomark.db');
    for (final folder in ['captures', 'signatures']) {
      final dir = Directory(p.join(docs.path, folder));
      if (!await dir.exists()) continue;
      await for (final e in dir.list()) {
        if (e is File) await add(e, '$folder/${p.basename(e.path)}');
      }
    }
    final logo = prefs.getString('logoPath');
    if (logo != null && await File(logo).exists()) {
      await add(File(logo), 'logo/${p.basename(logo)}');
    }
    final r = enc.close();
    if (r is Future) await r;
    await dbCopy.delete();
    await manifest.delete();
    return out;
  }

  /// Elige un respaldo .zip y lo restaura. Reemplaza los datos actuales.
  /// Devuelve false si el usuario canceló.
  Future<bool> pickAndRestore() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip']);
    final path = res?.files.single.path;
    if (path == null) return false;
    await restore(path);
    return true;
  }

  Future<void> restore(String zipPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    final work = Directory(p.join(tmp.path, 'restore_${DateTime.now().millisecondsSinceEpoch}'));
    await work.create(recursive: true);
    try {
      final r = Function.apply(extractFileToDisk, [zipPath, work.path]);
      if (r is Future) await r;

      final manifestFile = File(p.join(work.path, 'manifest.json'));
      final dbFile = File(p.join(work.path, 'geomark.db'));
      if (!await manifestFile.exists() || !await dbFile.exists()) {
        throw BackupException('El archivo no es un respaldo de GEO CUSCA SUR.');
      }
      final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final oldDocs = manifest['docsPath'] as String? ?? '';

      // 1. Archivos (fotos, firmas, logo)
      for (final folder in ['captures', 'signatures', 'logo']) {
        final src = Directory(p.join(work.path, folder));
        if (!await src.exists()) continue;
        final dst = Directory(folder == 'logo' ? docs.path : p.join(docs.path, folder));
        await dst.create(recursive: true);
        await for (final e in src.list()) {
          if (e is File) await e.copy(p.join(dst.path, p.basename(e.path)));
        }
      }

      // 2. Base de datos
      await AppDatabase.instance.close();
      await dbFile.copy(await AppDatabase.filePath());

      // 3. Rutas: si cambió la carpeta de la app, se corrigen.
      final db = await AppDatabase.instance.db;
      if (oldDocs.isNotEmpty && oldDocs != docs.path) {
        await db.rawUpdate('UPDATE captures SET file_path = replace(file_path, ?, ?)', [oldDocs, docs.path]);
        await db.rawUpdate(
            'UPDATE inspections SET signature_path = replace(signature_path, ?, ?) WHERE signature_path IS NOT NULL',
            [oldDocs, docs.path]);
      }

      // 4. Ajustes
      final prefs = await SharedPreferences.getInstance();
      final saved = (manifest['prefs'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final e in saved.entries) {
        final v = e.value;
        if (v == null) continue;
        if (e.key == 'logoPath' && v is String) {
          await prefs.setString('logoPath', p.join(docs.path, p.basename(v)));
        } else if (v is String) {
          await prefs.setString(e.key, v);
        } else if (v is bool) {
          await prefs.setBool(e.key, v);
        } else if (v is List) {
          await prefs.setStringList(e.key, v.map((x) => '$x').toList());
        }
      }
    } on BackupException {
      rethrow;
    } on DatabaseException catch (e) {
      throw BackupException('No se pudo restaurar la base de datos: $e');
    } catch (e) {
      throw BackupException('No se pudo restaurar el respaldo: $e');
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}
