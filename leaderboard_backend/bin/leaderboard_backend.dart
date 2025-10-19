import 'package:leaderboard_backend/leaderboard_backend.dart' as leaderboard_backend;

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:sqlite3/sqlite3.dart';

// Use env var for DB path and port so dev vs prod can differ
final dbPath = Platform.environment['LEADERBOARD_DB'] ?? 'leaderboard.db';
final port = int.tryParse(Platform.environment['PORT'] ?? '5000') ?? 5000;

late final Database db;

void initDb() {
  db = sqlite3.open(dbPath);
  db.execute('''
    CREATE TABLE IF NOT EXISTS leaderboard (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      score INTEGER NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
  ''');
}

Response jsonOk(Object obj) =>
    Response.ok(jsonEncode(obj), headers: {'Content-Type': 'application/json'});

void main() async {
  initDb();

  final router = Router();

  router.post('/submit', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    final username = (data['username'] as String?)?.trim();
    final score = data['score'] is int ? data['score'] as int : int.tryParse('${data['score']}');

    if (username == null || username.isEmpty || score == null) {
      return Response(400, body: jsonEncode({'error': 'Invalid input'}), headers: {'Content-Type': 'application/json'});
    }

    // Upsert: if user exists, update only if new score is higher.
    final select = db.prepare('SELECT score FROM leaderboard WHERE username = ?');
    final rows = select.select([username]);
    if (rows.isNotEmpty) {
      final current = rows.first['score'] as int;
      if (score > current) {
        final update = db.prepare('UPDATE leaderboard SET score = ?, created_at = CURRENT_TIMESTAMP WHERE username = ?');
        update.execute([score, username]);
        update.dispose();
      }
    } else {
      final insert = db.prepare('INSERT INTO leaderboard (username, score) VALUES (?, ?)');
      insert.execute([username, score]);
      insert.dispose();
    }
    select.dispose();

    return jsonOk({'status': 'ok'});
  });

  router.get('/top', (Request req) {
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 10;
    final result = db.select('SELECT username, score, created_at FROM leaderboard ORDER BY score DESC, created_at ASC LIMIT ?;', [limit]);
    final list = result.map((r) => {'username': r['username'], 'score': r['score'], 'when': r['created_at']}).toList();
    return jsonOk(list);
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders()) // allow your web frontend to call it
      .addHandler(router);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Listening on http://${server.address.host}:${server.port}, DB: $dbPath');
}