import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/capture_repository.dart';
import '../domain/capture_record.dart';
import 'preview_screen.dart';

/// Galería interna: SOLO muestra evidencias tomadas con la app
/// (nunca la galería del teléfono), agrupadas por día.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.repository});
  final CaptureRepository repository;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Future<List<CaptureRecord>> _items = widget.repository.all();

  Future<void> _reload() async {
    setState(() => _items = widget.repository.all());
    await _items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Mis evidencias'),
      ),
      body: FutureBuilder<List<CaptureRecord>>(
        future: _items,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text('Aún no hay fotos.\nLas evidencias que tomes aparecerán aquí.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            );
          }
          // Agrupar por fecha local
          final groups = <String, List<CaptureRecord>>{};
          for (final r in items) {
            final key = DateFormat('dd/MM/yyyy').format(r.time.local);
            groups.putIfAbsent(key, () => []).add(r);
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(slivers: [
              for (final e in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                    child: Text('${e.key} · ${e.value.length} fotos',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
                  itemCount: e.value.length,
                  itemBuilder: (_, i) => _Tile(record: e.value[i]),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.record});
  final CaptureRecord record;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PreviewScreen(record: record)),
      ),
      child: Stack(fit: StackFit.expand, children: [
        // cacheWidth: decodifica una versión pequeña (no los 12 MP completos)
        Image.file(File(record.filePath), fit: BoxFit.cover, cacheWidth: 300),
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: Colors.black54,
            child: Text(DateFormat('HH:mm').format(record.time.local),
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
        if (record.addressPending)
          const Positioned(
            right: 4,
            top: 4,
            child: Icon(Icons.cloud_off, size: 16, color: Colors.white),
          ),
      ]),
    );
  }
}
