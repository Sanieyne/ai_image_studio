import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/generation_item.dart';
import '../models/lora.dart';
import '../models/project_item.dart';

/// SQLite persistence (studio.db) + local disk image cache.
/// Images live in the app-support directory; the DB stores file paths.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;
  Directory? _imagesDir;

  Future<void> init() async {
    if (_db != null) return;

    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, 'ai_image_studio.db');

    _imagesDir = Directory(p.join(appDir.path, 'saved_generations'));
    if (!await _imagesDir!.exists()) {
      await _imagesDir!.create(recursive: true);
    }

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE generations (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            prompt TEXT NOT NULL,
            negative_prompt TEXT,
            aspect_ratio TEXT NOT NULL,
            model_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL,
            image_path TEXT,
            seed INTEGER,
            inference_time_ms INTEGER,
            active_loras TEXT,
            error_message TEXT,
            FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_generations_project ON generations(project_id)',
        );
      },
    );
  }

  Database get db {
    if (_db == null) throw StateError('DatabaseService is not initialized');
    return _db!;
  }

  // --- Projects ---

  Future<List<ProjectItem>> getAllProjects() async {
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(ProjectItem.fromMap).toList();
  }

  Future<void> insertProject(ProjectItem project) async {
    await db.insert('projects', project.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProjectTitle(String id, String newTitle) async {
    await db.update(
      'projects',
      {
        'title': newTitle,
        'updated_at': DateTime.now().millisecondsSinceEpoch
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleProjectPinned(String id, bool isPinned) async {
    await db.update(
      'projects',
      {
        'is_pinned': isPinned ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchProject(String id) async {
    await db.update(
      'projects',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteProject(String id) async {
    final generations = await getGenerationsForProject(id);
    for (final gen in generations) {
      if (gen.imagePath != null) {
        final f = File(gen.imagePath!);
        if (await f.exists()) await f.delete();
      }
    }
    await db.delete('generations',
        where: 'project_id = ?', whereArgs: [id]);
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // --- Generations ---

  Future<List<GenerationItem>> getGenerationsForProject(
      String projectId) async {
    final rows = await db.query(
      'generations',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'timestamp ASC',
    );

    final items = <GenerationItem>[];
    for (final r in rows) {
      Uint8List? bytes;
      final imagePath = r['image_path'] as String?;
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) bytes = await file.readAsBytes();
      }

      Map<String, LoraInfo> loras = {};
      final lorasRaw = r['active_loras'] as String?;
      if (lorasRaw != null && lorasRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(lorasRaw) as Map<String, dynamic>;
          loras = decoded.map((k, v) =>
              MapEntry(k, LoraInfo.fromJson(v as Map<String, dynamic>)));
        } catch (_) {}
      }

      GenerationStatus status;
      try {
        status = GenerationStatus.values
            .firstWhere((s) => s.name == r['status']);
      } catch (_) {
        status = GenerationStatus.failed;
      }

      items.add(GenerationItem(
        id: r['id'] as String,
        projectId: projectId,
        prompt: r['prompt'] as String,
        negativePrompt: r['negative_prompt'] as String? ?? '',
        aspectRatio: r['aspect_ratio'] as String? ?? '9:16',
        modelName: r['model_name'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (r['timestamp'] as int?) ?? 0),
        status: status,
        imagePath: imagePath,
        imageBytes: bytes,
        seed: r['seed'] as int?,
        inferenceTimeMs: r['inference_time_ms'] as int?,
        activeLoras: loras,
        errorMessage: r['error_message'] as String?,
      ));
    }
    return items;
  }

  Future<void> insertGeneration(GenerationItem item) async {
    await db.insert('generations', {
      'id': item.id,
      'project_id': item.projectId,
      'prompt': item.prompt,
      'negative_prompt': item.negativePrompt,
      'aspect_ratio': item.aspectRatio,
      'model_name': item.modelName,
      'timestamp': item.timestamp.millisecondsSinceEpoch,
      'status': item.status.name,
      'image_path': item.imagePath,
      'seed': item.seed,
      'inference_time_ms': item.inferenceTimeMs,
      'active_loras': jsonEncode(item.activeLoras.map(
          (k, v) => MapEntry(k, {'path': v.path, 'weight': v.weight}))),
      'error_message': item.errorMessage,
    });
    await db.update(
      'projects',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [item.projectId],
    );
  }

  Future<String?> updateGenerationResult({
    required String id,
    required GenerationStatus status,
    required Uint8List? bytes,
    required int? seed,
    required int? durationMs,
    required Map<String, LoraInfo> loras,
    String? error,
  }) async {
    String? savedFilePath;
    if (bytes != null && bytes.isNotEmpty && _imagesDir != null) {
      final file = File(p.join(_imagesDir!.path, '$id.jpg'));
      await file.writeAsBytes(bytes);
      savedFilePath = file.path;
    }
    await db.update(
      'generations',
      {
        'status': status.name,
        'image_path': savedFilePath,
        'seed': seed,
        'inference_time_ms': durationMs,
        'active_loras': jsonEncode(loras.map(
            (k, v) => MapEntry(k, {'path': v.path, 'weight': v.weight}))),
        'error_message': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return savedFilePath;
  }
}
