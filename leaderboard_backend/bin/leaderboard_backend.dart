import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

// ---- CONFIG ----
const dbFilePath = '/home/chaugment/Documents/2048_Server/Radial-2048/leaderboard_backend/bin/leaderboard.db';
const bindAddress = '127.0.0.1';
const bindPort = 8080;
const maxLeaderboardEntries = 100;
const maxSubmissionsPerMinute = 10;

final Map<String, List<DateTime>> submissionLog = {};

void main() async {
  // Ensure DB directory exists
  Directory(p.dirname(dbFilePath)).createSync(recursive: true);

  final db = sqlite3.open(dbFilePath, mode: OpenMode.readWriteCreate);
  _ensureSchema(db);
  print('DB path: $dbFilePath');

  final app = Router();

  app.get('/leaderboard', (Request req) => _handleGetLeaderboard(req, db));
  app.post('/leaderboard', (Request req) => _handlePostScore(req, db));

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(app);

  final server = await io.serve(handler, bindAddress, bindPort);
  print('Leaderboard server running on http://${server.address.host}:${server.port}');
}

void _ensureSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS scores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL,
      score INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
  ''');
  db.execute('CREATE INDEX IF NOT EXISTS idx_scores_score ON scores(score DESC);');
}

Future<Response> _handleGetLeaderboard(Request req, Database db) async {
  final limit = int.tryParse(req.url.queryParameters['limit'] ?? '50') ?? 50;
  final safeLimit = (limit <= 0 || limit > 1000) ? 50 : limit;

  final rs = db.select(
    'SELECT username, score, created_at FROM scores ORDER BY score DESC, created_at ASC LIMIT ?;',
    [safeLimit],
  );

  final rows = rs.map((row) => {
        'username': row['username'],
        'score': row['score'],
        'date': row['created_at'],
      }).toList();

  return Response.ok(jsonEncode(rows), headers: {'Content-Type': 'application/json'});
}

Future<Response> _handlePostScore(Request req, Database db) async {
  final ip = req.context['shelf.io.connection_info'] is HttpConnectionInfo
      ? (req.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address
      : 'unknown';

  final now = DateTime.now().toUtc();
  submissionLog.putIfAbsent(ip, () => []);
  submissionLog[ip] = submissionLog[ip]!.where((t) => now.difference(t).inMinutes < 1).toList();
  if (submissionLog[ip]!.length >= maxSubmissionsPerMinute) {
    return Response(429,
        body: jsonEncode({'error': 'Too many submissions'}),
        headers: {'Content-Type': 'application/json'});
  }

  final body = await req.readAsString();
  Map data;
  try {
    data = jsonDecode(body) as Map;
  } catch (e) {
    return Response(400,
        body: jsonEncode({'error': 'Invalid JSON'}),
        headers: {'Content-Type': 'application/json'});
  }

  print('Received POST: $data');

  final username = _sanitizeUsername(data['username']?.toString() ?? '');
  final score = (data['score'] is int) ? data['score'] : int.tryParse(data['score']?.toString() ?? '');

  if (username.isEmpty || score == null || score < 0) {
    return Response(400,
        body: jsonEncode({'error': 'Invalid username or score'}),
        headers: {'Content-Type': 'application/json'});
  }

  final stmt = db.prepare('INSERT INTO scores (username, score, created_at) VALUES (?, ?, ?);');
  try {
    print('Inserting: username=$username, score=$score');
    stmt.execute([username, score, DateTime.now().toUtc().toIso8601String()]);
    print('Insert successful');
  } catch (e, s) {
    print('Insert failed: $e\n$s');
  } finally {
    stmt.dispose();
  }


  submissionLog[ip]!.add(now);

  _trimToTopN(db, maxLeaderboardEntries);

  return Response.ok(jsonEncode({'status': 'ok'}), headers: {'Content-Type': 'application/json'});
}

String _sanitizeUsername(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\n\r\t]'), ' ');
  s = s.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  if (s.length > 32) s = s.substring(0, 32);
  return s;
}

void _trimToTopN(Database db, int n) {
  if (n <= 0) return;
  db.execute('''
    DELETE FROM scores
    WHERE id NOT IN (
      SELECT id FROM scores ORDER BY score DESC, created_at ASC LIMIT ?
    );
  ''', [n]);
}
