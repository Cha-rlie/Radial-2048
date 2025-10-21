
// File: dart_leaderboard_server.dart
// Purpose: simple persistent leaderboard API using Dart + shelf + sqlite3
// Instructions below show how to install, run as a service, nginx proxy, and
// how your Flutter web game should call the API.

/*
Overview (what this file provides):
- REST API endpoints:
  GET  /leaderboard?limit=50         -> returns top scores desc
  POST /leaderboard                  -> submit a score (username, score)
  GET  /player/<username>            -> get all scores for a player (optional)
- Uses sqlite3 for persistent storage (file: leaderboard.db)
- Minimal input validation, SQL prepared statements, basic rate limiting in-memory
- CORS enabled so your Flutter web app can fetch directly

Notes before running:
- Dart SDK >= 2.18 recommended (install on Raspberry Pi and dev laptop)
- Add dependencies in pubspec.yaml: shelf, shelf_router, shelf_cors_headers, sqlite3, path
- On the Pi, install SQLite3 (system package) so dart sqlite3 can link to it.
- Run with: dart run dart_leaderboard_server.dart
- For production, run as a systemd service and put nginx in front of it.

Security & design
- This is intended as a *simple* leaderboard for a hobby/self-hosted game.
- It does NOT implement user accounts, password hashing, or strong anti-cheat.
  If you want players to *prove* scores (avoid cheating), you'll need server-side
  verification inside your game logic or a signed-submission scheme.

Database schema
- Table: scores(id INTEGER PK, username TEXT, score INTEGER, created_at TEXT)
- Index on score (desc) for fast leaderboard queries

*/

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:sqlite3/sqlite3.dart';

// CONFIG
const dbFileName = 'leaderboard.db';
const bindAddress = '127.0.0.1'; // bind to localhost; nginx will proxy
const bindPort = 8080;
const maxLeaderboardEntries = 100; // keep top N if you want trimming

// Basic in-memory rate limiter (per IP) — simple and not bulletproof
const maxSubmissionsPerMinute = 10; // tune as needed
final Map<String, List<DateTime>> submissionLog = {};

void main() async {
  // open/create database
  final dbPath = p.join(Directory.current.path, dbFileName);
  final db = sqlite3.open(dbPath);
  _ensureSchema(db);

  final app = Router();

  // Leaderboard routes
  app.get('/leaderboard', (Request req) => _handleGetLeaderboard(req, db));
  app.get('/leaderboard/', (Request req) => _handleGetLeaderboard(req, db));

  app.post('/leaderboard', (Request req) => _handlePostScore(req, db));
  app.post('/leaderboard/', (Request req) => _handlePostScore(req, db));

  // Player routes
  app.get('/player/<username>', (Request req, String username) => _handleGetPlayer(req, db, username));
  app.get('/player/<username>/', (Request req, String username) => _handleGetPlayer(req, db, username));


  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(app);

  final server = await io.serve(handler, bindAddress, bindPort);
  print('Leaderboard server listening on http://${server.address.host}:${server.port}');
}

// Ensure the scores table and index exist
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

// GET /leaderboard?limit=50
Future<Response> _handleGetLeaderboard(Request req, Database db) async {
  final qs = req.url.queryParameters;
  final limit = int.tryParse(qs['limit'] ?? '') ?? 50;
  final safeLimit = (limit <= 0 || limit > 1000) ? 50 : limit;

  final ResultSet rs = db.select('SELECT username, score, created_at FROM scores ORDER BY score DESC, created_at ASC LIMIT ?;', [safeLimit]);
  final List<Map<String, dynamic>> rows = rs.map((row) => {
        'username': row['username'],
        'score': row['score'],
        'date': row['created_at'],
      }).toList();

  return Response.ok(jsonEncode(rows), headers: {'Content-Type': 'application/json'});
}

// POST /leaderboard { username, score }
Future<Response> _handlePostScore(Request req, Database db) async {
  // Simple rate limiting per remote IP
  final ip = req.context['shelf.io.connection_info'] is HttpConnectionInfo
      ? (req.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address
      : 'unknown';

  final now = DateTime.now().toUtc();
  submissionLog.putIfAbsent(ip, () => []);
  submissionLog[ip] = submissionLog[ip]!.where((t) => now.difference(t).inMinutes < 1).toList();
  if (submissionLog[ip]!.length >= maxSubmissionsPerMinute) {
    return Response(429, body: jsonEncode({'error': 'Too many submissions'}), headers: {'Content-Type': 'application/json'});
  }

  final body = await req.readAsString();
  Map data;
  try {
    data = jsonDecode(body) as Map;
  } catch (e) {
    return Response(400, body: jsonEncode({'error': 'Invalid JSON'}), headers: {'Content-Type': 'application/json'});
  }

  final rawUsername = (data['username'] ?? '').toString();
  final rawScore = data['score'];

  // Validation
  final username = _sanitizeUsername(rawUsername);
  if (username.isEmpty) {
    return Response(400, body: jsonEncode({'error': 'Invalid username'}), headers: {'Content-Type': 'application/json'});
  }

  final score = (rawScore is int) ? rawScore : int.tryParse(rawScore?.toString() ?? '');
  if (score == null || score < 0) {
    return Response(400, body: jsonEncode({'error': 'Invalid score'}), headers: {'Content-Type': 'application/json'});
  }

  // Insert using a prepared statement
  final stmt = db.prepare('INSERT INTO scores (username, score, created_at) VALUES (?, ?, ?);');
  try {
    stmt.execute([username, score, DateTime.now().toUtc().toIso8601String()]);
  } finally {
    stmt.dispose();
  }

  submissionLog[ip]!.add(now);

  // Optional: trim table to keep only top N rows
  _trimToTopN(db, maxLeaderboardEntries);

  return Response.ok(jsonEncode({'status': 'ok'}), headers: {'Content-Type': 'application/json'});
}

Future<Response> _handleGetPlayer(Request req, Database db, String username) async {
  final clean = _sanitizeUsername(username);
  if (clean.isEmpty) return Response(400, body: jsonEncode({'error': 'Invalid username'}), headers: {'Content-Type': 'application/json'});

  final rs = db.select('SELECT score, created_at FROM scores WHERE username = ? ORDER BY score DESC, created_at ASC LIMIT 100;', [clean]);
  final rows = rs.map((r) => {'score': r['score'], 'date': r['created_at']}).toList();
  return Response.ok(jsonEncode({'username': clean, 'scores': rows}), headers: {'Content-Type': 'application/json'});
}

String _sanitizeUsername(String raw) {
  // Simple sanitization: trim, remove newlines, limit length, remove control chars
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'[\n\r\t]'), ' ');
  if (s.length > 32) s = s.substring(0, 32);
  // Remove characters that might cause weird display issues
  s = s.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  return s;
}

void _trimToTopN(Database db, int n) {
  if (n <= 0) return;
  // Delete entries not in top N by score (ties resolved by earlier created_at)
  // This runs a DELETE with subquery; inexpensive for small N, but might be heavier on large tables.
  db.execute('''
    DELETE FROM scores
    WHERE id NOT IN (
      SELECT id FROM scores ORDER BY score DESC, created_at ASC LIMIT ?
    );
  ''', [n]);
}

/*

--- Deployment steps (short checklist) ---

1) Install Dart on Raspberry Pi (arm) and your dev machine. See official Dart docs for platform-specific instructions.

2) Create pubspec.yaml in same folder:

name: leaderboard_server
environment:
  sdk: '>=2.19.0 <3.0.0'

dependencies:
  shelf: ^1.4.0
  shelf_router: ^1.0.0
  shelf_cors_headers: ^0.2.0
  sqlite3: ^1.3.0
  path: ^1.8.0

Run: dart pub get

3) Ensure system SQLite dev libs exist on Pi. On Debian/Raspberry Pi OS: sudo apt-get install libsqlite3-dev

4) Run server for debugging:
   dart run dart_leaderboard_server.dart
   -> visit http://<pi-ip>:8080/leaderboard to see JSON (CORS enabled)

5) Configure nginx (example snippet):

server {
    listen 80;
    server_name your.domain.or.ip;

    root /var/www/your_flutter_build; # where you put Flutter web build

    location / {
        try_files $uri $uri/ =404;
    }

    location /leaderboard {
        proxy_pass http://127.0.0.1:8080/leaderboard;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

6) Systemd service file example (/etc/systemd/system/leaderboard.service):

[Unit]
Description=Leaderboard Dart Server
After=network.target

[Service]
WorkingDirectory=/home/pi/leaderboard
ExecStart=/usr/bin/dart run dart_leaderboard_server.dart
Restart=on-failure
User=pi

[Install]
WantedBy=multi-user.target

Enable and start:
sudo systemctl daemon-reload
sudo systemctl enable leaderboard
sudo systemctl start leaderboard

7) Backups: Copy leaderboard.db regularly. Example cron to copy daily:
0 3 * * * cp /home/pi/leaderboard/leaderboard.db /home/pi/leaderboard/backups/leaderboard-$(date +"%Y%m%d").db

8) Flutter client example (Dart HTTP code snippet) — call the proxied nginx path so browser sees same origin:

// send a score
Future<void> submitScore(String username, int score) async {
  final url = Uri.parse('/leaderboard'); // relative path when hosted under same domain
  final resp = await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'score': score}));
  if (resp.statusCode != 200) {
    // handle failure (parse JSON error message)
    print('Failed: ' + resp.body);
  }
}

// get leaderboard
Future<List<dynamic>> fetchLeaderboard([int limit = 50]) async {
  final url = Uri.parse('/leaderboard?limit=$limit');
  final resp = await http.get(url);
  if (resp.statusCode == 200) return jsonDecode(resp.body) as List<dynamic>;
  return [];
}

Notes: If you test locally (during dev) you may call the Pi's full http://<pi-ip>:8080 path; when deploying behind nginx, use the relative "/leaderboard" path so the browser's origin is the same and you avoid CORS complexities.

--- Anti-cheat and validation ideas (optional) ---
- Server-side verification: run the game logic on server for high-stakes prizes.
- Signed submissions: issue a short-lived token when a game starts and include it at submission to reduce trivial spoofing.
- Rate limiting & heuristics: detect repeated high scores from same IP/account and flag for review.

--- Troubleshooting & tips ---
- If sqlite3 package fails to load, install libsqlite3-dev and rebuild (dart pub get again). On some platforms you may need environment variables pointing to the sqlite lib.
- For development, run the server with stdout logs visible. For production, check `journalctl -u leaderboard` for service logs.
- Use `sqlite3 leaderboard.db` on the Pi to run ad-hoc queries and inspect data.

*/
