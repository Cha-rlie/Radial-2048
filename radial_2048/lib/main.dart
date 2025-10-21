import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyGameState(),
      child: MaterialApp(
        title: 'Radial 2048',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

enum Move {
  clockwise,
  antiClockwise,
  inwards,
  outwards
}

class MyGameState extends ChangeNotifier {
  static var random = Random();

  // Use compile-time flags to switch modes:
  // flutter run --dart-define=USE_MOCK=false --dart-define=BACKEND_URL=http://rpi:5000
  static const bool useMockBackend = false; //bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const String backendBase = '/leaderboard';//String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8080');

  late List<List<int>> grid;
  var empty = [];
  int maxNum = 0;
  late List<List<int>> lastMove;
  List<int> wallPoses = [];
  int moveNum = 0;
  var undid = false;
  var shouldRepaint = false;
  List<Map<String, dynamic>> leaderboard = [
    {"Username": "Alice", "Score": 250, "Date": "2025-10-19"},
    {"Username": "Bob", "Score": 200, "Date": "2025-10-18"},
    {"Username": "Charlie", "Score": 180, "Date": "2025-10-17"},
    {"Username": "Diana", "Score": 150, "Date": "2025-10-16"},
  ];
  bool gameOver = false;
  int score = 0;
  int lastScore = 0;
  
  void printGrid() {
    for (int i = 0; i < 4; i++) {
      debugPrint("${grid[i]}");
    }
  }

  void setUp() {
    grid = List.generate(4, (i) => List.generate(4, (j) => 0));
    lastMove = grid.map((row) => List<int>.from(row)).toList();
    moveNum = 0;
    maxNum = 0;
    score = 0;
    lastScore = 0;
    // Keep track of empties
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        empty.add([row, col]);
      }
    }
    wallPoses = List.generate(4, (i) => random.nextInt(4));
    makeNewTile();
    makeNewTile();
    printGrid();

    refreshLeaderboard();

    notifyListeners();
  }

  void makeNewTile() {
    // Find a random empty space on the grid
    if (empty.isNotEmpty) {
      var tilePos = empty[random.nextInt(empty.length)];
      empty.remove(tilePos);
      // Produce a new number with a 10% of being a 4 and a 90% chance of being a 2
      int newValue = random.nextInt(10) == 0 ? 4 : 2;
      grid[tilePos[0]][tilePos[1]] = newValue;
      if (newValue > maxNum) maxNum = newValue;
    } else {
      gameOver = true;
      //TODO: handle game over state
      debugPrint("GAMEOVER!");
    }
  }

  void doMove(Move movement) {
    lastMove = grid.map((row) => List<int>.from(row)).toList();
    switch (movement) {
      case Move.clockwise:
        debugPrint("clockwise");
        // Repeat this for all of the sectors
        // Goes from bottom-right clockwise
        for (var radi = 0; radi < 4; radi++) {
          List<int> newNums = [];
          int numToMatch = -1;
          for (var sec = 3; sec > -1; sec--) {
            debugPrint("wallPose for this radi ($radi) = ${wallPoses[radi]}");
            int wallAdjustedSec = (sec + wallPoses[radi])%4;
            debugPrint("1");
            int currentNum = grid[radi][wallAdjustedSec];
            debugPrint("2");
            // If the next cell is not empty
            debugPrint("currentNum = $currentNum");
            debugPrint("NumToMatch = $numToMatch");
            if (currentNum != 0) {
              if (numToMatch == -1) {numToMatch = currentNum;}
              else if (currentNum == numToMatch) {
                newNums.add(currentNum*2);
                lastScore = score;
                addToScore(currentNum*2);
                if (currentNum*2 > maxNum) {maxNum = currentNum*2;}
                numToMatch = -1;
              } else {
                newNums.add(numToMatch);
                numToMatch = currentNum;
              }
            }
          }
          if (numToMatch != -1) {newNums.add(numToMatch);}
          debugPrint("newNums = $newNums");
          // Put new list in the grid
          for (var sec = 0; sec < 4; sec++) {
            int wallAdjustedSec = (3 - sec + wallPoses[radi])%4;
            debugPrint("3 + sec = $sec + walladj = $wallAdjustedSec + newNums = $newNums");
            if (sec < newNums.length) {
              debugPrint("4");
              grid[radi][wallAdjustedSec] = newNums[sec];
              debugPrint("5");
              empty.remove([radi, wallAdjustedSec]); // No error is thrown if not in list
              debugPrint("6");
            } else {
              debugPrint("7");
              grid[radi][wallAdjustedSec] = 0;
              debugPrint("8");
              if (!empty.contains([radi, wallAdjustedSec])) {empty.add([radi, wallAdjustedSec]);} //make unique
              debugPrint("9");
            }
          }
        }
        break;


        // // Repeat this for all of the rows
        // for (var i = 0; i < 4; i++) {
        //   // Keep track of the next spot to fill
        //   var nextPos = 3;
        //   for (var j = 3; j > -1; j--) { // Loop through the cells in the row
        //     if (grid[i][j] != 0) { // If the cell is not empty
        //       // If the next cell exists and is equal to this one
        //       if (j > 0 && grid[i][j-1] == grid[j][i]) {
        //         int newValue = grid[i][j]*2;
        //         grid[i][nextPos] = newValue;
        //         grid[i][j-1] = 0;
        //         empty.add([i, j-1]);
        //         if (newValue > maxNum) maxNum = newValue;
        //       }
        //       else {
        //         grid[i][nextPos] = grid[i][j];
        //       }
        //       // Clear the cells if something has been moved
        //       if (nextPos != j) {
        //         grid[i][j] = 0;
        //         empty.add([i, j]);
        //         empty.remove([i, nextPos]);
        //       }
        //       // ^ Fill up the next position cell as required
        //       nextPos -= 1; // Increment the next available position
        //     }
        //   }
        // }
        // break;
      case Move.antiClockwise:
        debugPrint("antiClockwise");
        // Repeat this for all of the sectors
        // Goes from bottom-right clockwise
        for (var radi = 0; radi < 4; radi++) {
          List<int> newNums = [];
          int numToMatch = -1;
          for (var sec = 0; sec < 4; sec++) {
            debugPrint("wallPose for this radi ($radi) = ${wallPoses[radi]}");
            int wallAdjustedSec = (sec + wallPoses[radi])%4;
            debugPrint("1");
            int currentNum = grid[radi][wallAdjustedSec];
            debugPrint("2");
            // If the next cell is not empty
            debugPrint("currentNum = $currentNum");
            debugPrint("NumToMatch = $numToMatch");
            if (currentNum != 0) {
              if (numToMatch == -1) {numToMatch = currentNum;}
              else if (currentNum == numToMatch) {
                newNums.add(currentNum*2);
                lastScore = score;
                addToScore(currentNum*2);
                if (currentNum*2 > maxNum) {maxNum = currentNum*2;}
                numToMatch = -1;
              } else {
                newNums.add(numToMatch);
                numToMatch = currentNum;
              }
            }
          }
          if (numToMatch != -1) {newNums.add(numToMatch);}
          debugPrint("newNums = $newNums");
          // Put new list in the grid
          for (var sec = 0; sec < 4; sec++) {
            int wallAdjustedSec = (sec + wallPoses[radi])%4;
            debugPrint("3 + sec = $sec + walladj = $wallAdjustedSec + newNums = $newNums");
            if (sec < newNums.length) {
              debugPrint("4");
              grid[radi][wallAdjustedSec] = newNums[sec];
              debugPrint("5");
              empty.remove([radi, wallAdjustedSec]); // No error is thrown if not in list
              debugPrint("6");
            } else {
              debugPrint("7");
              grid[radi][wallAdjustedSec] = 0;
              debugPrint("8");
              if (!empty.contains([radi, wallAdjustedSec])) {empty.add([radi, wallAdjustedSec]);} //make unique
              debugPrint("9");
            }
          }
        }
        break;

        // // Repeat this for all of the rows
        // for (var i = 0; i < 4; i++) {
        //   // Keep track of the next spot to fill
        //   var nextPos = 0;
        //   for (var j = 0; j < 4; j++) { // Loop through the cells in the row
        //     if (grid[i][j] != 0) { // If the cell is not empty
        //       // If the next cell exists and is equal to this one
        //       if (j < 3 && grid[i][j+1] == grid[j][i]) {
        //         int newValue = grid[i][j]*2;
        //         grid[i][nextPos] = newValue;
        //         grid[i][j+1] = 0;
        //         empty.add([i, j+1]);
        //         if (newValue > maxNum) maxNum = newValue;
        //       }
        //       else {
        //         grid[i][nextPos] = grid[i][j];
        //       }
        //       // Clear the cells if something has been moved
        //       if (nextPos != j) {
        //         grid[i][j] = 0;
        //         empty.add([i, j]);
        //         empty.remove([i, nextPos]);
        //       }
        //       // ^ Fill up the next position cell as required
        //       nextPos += 1; // Increment the next available position
        //     }
        //   }
        // }
        // break;
      case Move.inwards:
        // Repeat this for all of the sectors
        // Goes from bottom-right clockwise
        for (var sec = 0; sec < 4; sec++) {
          List<int> newNums = [];
          int numToMatch = -1;
          for (var radi = 0; radi < 4; radi++) {
            int currentNum = grid[radi][sec];
            // If the next cell is not empty
            debugPrint("inwards");
            debugPrint("currentNum = $currentNum");
            debugPrint("NumToMatch = $numToMatch");
            if (currentNum != 0) {
              if (numToMatch == -1) {numToMatch = currentNum;}
              else if (currentNum == numToMatch) {
                newNums.add(currentNum*2);
                lastScore = score;
                addToScore(currentNum*2);
                if (currentNum*2 > maxNum) {maxNum = currentNum*2;}
                numToMatch = -1;
              } else {
                newNums.add(numToMatch);
                numToMatch = currentNum;
              }
            }
          }
          if (numToMatch != -1) {newNums.add(numToMatch);}
          debugPrint("newNums = $newNums");
          // Put new list in the grid
          for (var radi = 0; radi < 4; radi++) {
            if (radi < newNums.length) {
              grid[radi][sec] = newNums[radi];
              empty.remove([radi, sec]); // No error is thrown if not in list
            } else {
              grid[radi][sec] = 0;
              if (!empty.contains([radi, sec])) {empty.add([radi, sec]);}
            }
          }
        }
        // for (var i = 0; i < 4; i++) {
        //   var nextPos = 0; // Keep track of the next spot to fill
        //   for (var j = 0; j < 4; j++) { // Loop through the cells in the column
        //     if (grid[j][i] != 0) { // If the cell is not empty
        //       // If the next cell exists and is equal to this one
        //       if (j < 3 && grid[j+1][i] == grid[j][i]) {
        //         int newValue = grid[j][i]*2;
        //         grid[nextPos][i] = newValue;
        //         grid[j+1][i] = 0;
        //         empty.add([j+1, i]);
        //         if (newValue > maxNum) maxNum = newValue;
        //       }
        //       else {
        //         grid[nextPos][i] = grid[j][i];
        //       }
        //       // Clear the cells if something has been moved
        //       if (nextPos != j) {
        //         grid[j][i] = 0;
        //         empty.add([j, i]);
        //         empty.remove([nextPos, i]);
        //       }
        //       // ^ Fill up the next position cell as required
        //       nextPos += 1; // Increment the next available position
        //     }
        //   }
        // }
        break;
      case Move.outwards:
        // Repeat this for all of the columns
        // Goes from bottom-right clockwise
        for (var sec = 0; sec < 4; sec++) {
          List<int> newNums = [];
          int numToMatch = -1;
          for (var radi = 3; radi > -1; radi--) {
            int currentNum = grid[radi][sec];
            debugPrint("outwards");
            debugPrint("currentNum = $currentNum");
            debugPrint("NumToMatch = $numToMatch");
            // If the next cell is not empty
            if (currentNum != 0) {
              if (numToMatch == -1) {numToMatch = currentNum;}
              else if (currentNum == numToMatch) {
                newNums.add(currentNum*2);
                if (currentNum*2 > maxNum) {maxNum = currentNum*2;}
                numToMatch = -1;
              } else {
                newNums.add(numToMatch);
                lastScore = score;
                addToScore(currentNum*2);
                numToMatch = currentNum;
              }
            }
          }
          if (numToMatch != -1) {newNums.add(numToMatch);}
          debugPrint("newNums = $newNums");
          // Put new list in the grid
          for (var radi = 0; radi < 4; radi++) {
            if (radi < newNums.length) {
              grid[3-radi][sec] = newNums[radi];
              empty.remove([3-radi, sec]); // No error is thrown if not in list
            } else {
              grid[3-radi][sec] = 0;
              if (!empty.contains([radi, 3-sec])) {empty.add([3-radi, sec]);}
            }
          }
        }


        // Repeat this for all of the columns
        // for (var i = 0; i < 4; i++) {
        //   var nextPos = 3; // Keep track of the next spot to fill
        //   for (var j = 3; j > -1; j--) { // Loop through the cells in the column
        //     if (grid[j][i] != 0) { // If the cell is not empty
        //       // If the next cell exists and is equal to this one
        //       if (j > 0 && grid[j-1][i] == grid[j][i]) {
        //         int newValue = grid[j][i]*2;
        //         grid[nextPos][i] = newValue;
        //         grid[j-1][i] = 0;
        //         empty.add([j-1, i]);
        //         if (newValue > maxNum) maxNum = newValue;
        //       }
        //       else {
        //         grid[nextPos][i] = grid[j][i];
        //       }
        //       // Clear the cells if something has been moved
        //       if (nextPos != j) {
        //         grid[j][i] = 0;
        //         empty.add([j, i]);
        //         empty.remove([nextPos, i]);
        //       }
        //       // ^ Fill up the next position cell as required
        //       nextPos -= 1; // Increment the next available position
        //     }
        //   }
        // }
        break;
    }
    moveNum += 1;
    undid = false;
    makeNewTile();
    shouldRepaint = true;
    debugPrint('a move has actually been done');
    printGrid();
    notifyListeners();
  }

  void undo() {
    grid = lastMove.map((row) => List<int>.from(row)).toList();
    moveNum -= 1;
    undid = true;
    shouldRepaint = true;
    score = lastScore;
    notifyListeners();
  }

  void addToScore(int add) {
    score += add;
  }

Future<void> submitScore(String username) async {
  if (username.isEmpty) username = "Anonymous";

  // Optimistic local update (optional)
  leaderboard.insert(0, {
    'username': username,
    'score': score,
    'date': DateTime.now().toIso8601String()
  });

  leaderboard.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
  if (leaderboard.length > 100) {
    leaderboard = leaderboard.sublist(0, 100);
  }
  notifyListeners();

  // Skip backend if using mock
  if (useMockBackend) return;

  try {
    final url = Uri.parse('/leaderboard'); // relative path via nginx
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"username": username, "score": score}),
    );

    if (resp.statusCode != 200) {
      debugPrint('submitScore failed (${resp.statusCode}): ${resp.body}');
    }
  } catch (e) {
    debugPrint('submitScore exception: $e');
  }
}



Future<List<Map<String, dynamic>>> getLeaderboard([int limit = 100]) async {
  if (useMockBackend) return leaderboard;

  try {
    final url = Uri.parse('/leaderboard?limit=$limit');
    final resp = await http.get(url);

    if (resp.statusCode == 200) {
      final List<dynamic> decoded = jsonDecode(resp.body);

      // Map backend JSON to frontend UI keys
      leaderboard = decoded.map<Map<String, dynamic>>((e) {
        return {
          'username': e['username'], // lowercase matches backend
          'score': e['score'],
          'date': e['date'],         // lowercase matches backend
        };
      }).toList();

      notifyListeners();
      return leaderboard;
    } else {
      debugPrint('getLeaderboard failed (${resp.statusCode}): ${resp.body}');
    }
  } catch (e) {
    debugPrint('getLeaderboard exception: $e');
  }

  return leaderboard;
}


  void refreshLeaderboard() {
    getLeaderboard(100);
    notifyListeners();
  }

}

class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    context.read<MyGameState>().setUp();
  }
  
  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = GamePage();
        break;
      case 1:
        page = LeaderboardPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }
    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                extended: constraints.maxWidth >= 600,
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.games),
                    label: Text('Game'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.leaderboard),
                    label: Text('Leaderboard'),
                  ),
                ],
                selectedIndex: selectedIndex,
                onDestinationSelected: (value) {
                  setState(() {selectedIndex = value;});
                },
              ),
            ),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: page,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class GamePage extends StatefulWidget {
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  FocusNode _focusNode = FocusNode();
  late ValueNotifier<int> repaintNotifier = ValueNotifier(0);
  late List<List<int>> grid;
  late List<int> wallPoses;

  // Keep track of widget size
  final GlobalKey myWidgetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    repaintNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.keyW:
          debugPrint('Outwards');
          context.read<MyGameState>().doMove(Move.outwards);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.outwards); repaintNotifier.value++;});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final renderBox = myWidgetKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              StatusOverlay.show(
                context,
                icon: Icons.zoom_out_map,
                message: "Outwards",
                targetRect: Rect.fromLTWH(
                  renderBox.localToGlobal(Offset.zero).dx,
                  renderBox.localToGlobal(Offset.zero).dy,
                  renderBox.size.width,
                  renderBox.size.height/10
                  ),
                );
              }
          });
          //var renderBox = myWidgetKey.currentContext!.findRenderObject() as RenderBox;
          //StatusOverlay.show(context, icon: Icons.zoom_out_map, message: "Outwards", targetRect: Rect.fromLTWH(renderBox.localToGlobal(Offset.zero).dx, renderBox.localToGlobal(Offset.zero).dy, renderBox.size.width, renderBox.size.height/10));
          debugPrint('Outwards');
          break;
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.keyS:
          debugPrint('Inwards');
          context.read<MyGameState>().doMove(Move.inwards);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.inwards); repaintNotifier.value++;});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final renderBox = myWidgetKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              StatusOverlay.show(
                context,
                icon: Icons.zoom_in_map,
                message: "Inwards",
                targetRect: Rect.fromLTWH(
                  renderBox.localToGlobal(Offset.zero).dx,
                  renderBox.localToGlobal(Offset.zero).dy,
                  renderBox.size.width,
                  renderBox.size.height/10
                  ),
                );
              }
          });
          //final renderBox = myWidgetKey.currentContext!.findRenderObject() as RenderBox;
          //StatusOverlay.show(context, icon: Icons.zoom_in_map, message: "Inwards", targetRect: Rect.fromLTWH(renderBox.localToGlobal(Offset.zero).dx, renderBox.localToGlobal(Offset.zero).dy, renderBox.size.width, renderBox.size.height));
          debugPrint('Inwards');
          break;
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.keyD:
          debugPrint('Clockwise');
          context.read<MyGameState>().doMove(Move.clockwise);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.clockwise); repaintNotifier.value++;});
                    WidgetsBinding.instance.addPostFrameCallback((_) {
            final renderBox = myWidgetKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              StatusOverlay.show(
                context,
                icon: Icons.rotate_right,
                message: "Clockwise",
                targetRect: Rect.fromLTWH(
                  renderBox.localToGlobal(Offset.zero).dx,
                  renderBox.localToGlobal(Offset.zero).dy,
                  renderBox.size.width,
                  renderBox.size.height/10
                  ),
                );
              }
          });
          //final renderBox = myWidgetKey.currentContext!.findRenderObject() as RenderBox;
          //StatusOverlay.show(context, icon: Icons.rotate_right, message: "Clockwise", targetRect: Rect.fromLTWH(renderBox.localToGlobal(Offset.zero).dx, renderBox.localToGlobal(Offset.zero).dy, renderBox.size.width, renderBox.size.height));
          debugPrint('Clockwise');
          break;
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.keyA:
          debugPrint('Anticlockwise');
          context.read<MyGameState>().doMove(Move.antiClockwise);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.antiClockwise); repaintNotifier.value++;});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final renderBox = myWidgetKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              StatusOverlay.show(
                context,
                icon: Icons.rotate_left,
                message: "Anticlockwise",
                targetRect: Rect.fromLTWH(
                  renderBox.localToGlobal(Offset.zero).dx,
                  renderBox.localToGlobal(Offset.zero).dy,
                  renderBox.size.width,
                  renderBox.size.height/10
                  ),
                );
              }
          });
          //final renderBox = myWidgetKey.currentContext!.findRenderObject() as RenderBox;
          //StatusOverlay.show(context, icon: Icons.rotate_left, message: "Anticlockwise", targetRect: Rect.fromLTWH(renderBox.localToGlobal(Offset.zero).dx, renderBox.localToGlobal(Offset.zero).dy, renderBox.size.width, renderBox.size.height));
          debugPrint('Anticlockwise');
          break;
        default:
          break;
      }
    }
  }

  void onSwipe(String dir) {
    switch (dir) {
      case "Up":
        _onKeyEvent(KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyW, logicalKey: LogicalKeyboardKey.keyW, timeStamp: Duration(milliseconds: 200)));
        break;
      case "Down":
        _onKeyEvent(KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyS, logicalKey: LogicalKeyboardKey.keyS, timeStamp: Duration(milliseconds: 200)));
        break;
      case "Left":
        _onKeyEvent(KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyA, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration(milliseconds: 200)));
        break;
      case "Right":
        _onKeyEvent(KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyD, logicalKey: LogicalKeyboardKey.keyD, timeStamp: Duration(milliseconds: 200)));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    grid = context.watch<MyGameState>().grid;
    wallPoses = context.watch<MyGameState>().wallPoses;
    //var renderBox = myCanvasKey.currentContext!.findRenderObject() as RenderBox;
    return KeyboardListener(  
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) => _onKeyEvent(event),
      child: GestureDetector(
        onVerticalDragEnd:(details) {
          if (details.primaryVelocity! < 0) onSwipe("Up");
            else if (details.primaryVelocity! > 0) onSwipe("Down");
        },
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < 0) onSwipe("Left");
          else if (details.primaryVelocity! > 0) onSwipe("Right");
        },
        child: LayoutBuilder(builder: (context, constraints) {
        return Padding(padding: EdgeInsets.all(constraints.biggest.shortestSide*0.02), child: Column(
          key: myWidgetKey,
          children: [
            // TODO: add a tutorial question mark button here
            Row(
              children: [
                Container(decoration: BoxDecoration(border: Border.all(color: Colors.deepOrangeAccent, width: 2), borderRadius: BorderRadius.circular(8)), child: Column(children: [Text('  Score: ${context.watch<MyGameState>().score}  ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                Text('  Move Count: ${context.watch<MyGameState>().moveNum}   ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                Text('  Max Number: ${context.watch<MyGameState>().maxNum}   ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))])),
                Spacer(),
                ElevatedButton.icon(onPressed: () => showDialog(context: context, barrierDismissible: true, builder: (BuildContext context) {
                  return AlertDialog(title: Text('How to play!'), content: Text('1. Use WASD or arrow keys, or even swipe your fingers to move and rotate the tiles.\n2. Tiles can be pushed outwards to the edge, or inside to the centre.\n3. They can be rotated clockwise or anticlockwise and each circle will go until its own wall.\n4. Two tiles with the same number can merge and they add to your score!\n5. The game ends when the whole board is full or you end it.\n6. Share your results on the leaderboard!'), actions: <Widget>[
                              TextButton(
                                child: Text('Ok'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                })
                            ]);
                }), icon: Icon(Icons.help), label: Text("Help"))
              ],
            ),
            Center( child: LayoutBuilder(builder: (context, constraints) {
              // Determine the maximum size for the canvas to fit within parent
              final double maxAvailable = constraints.biggest.shortestSide; 
              final double canvasSize = maxAvailable * 0.5; // 60% of smaller dimension
              final double padding = canvasSize * 0.02;     // 20% of canvas
              return Padding(
              padding: EdgeInsets.all(padding),
              child: CustomPaint(painter: RadialPainter(gameGrid: grid, wallPoses: wallPoses, repaint: repaintNotifier), child: SizedBox.fromSize(size: Size.square(canvasSize))
            ));})
            ),
            // TODO: Make undo button update canvas
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (context.read<MyGameState>().moveNum > 0) {
                      if (!context.read<MyGameState>().undid) {
                        context.read<MyGameState>().undo();
                      } else {
                        showDialog(context: context, barrierDismissible: true,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('No can do!'),
                              content: Text('You can only undo once at a time, try making a move instead!'),
                              actions: <Widget>[
                              TextButton(
                                child: Text('Ok'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                })
                            ]
                            );
                          });
                        }
                      } else {
                        showDialog(context: context, barrierDismissible: true,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('No can do!'),
                              content: Text("You haven't done a move yet to undo,\ntry making a move instead!"),
                              actions: <Widget>[
                              TextButton(
                                child: Text('Ok'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                })
                              ]
                            );
                          });
                    }
                  },
                  icon: Icon(Icons.undo),
                  label: Text('Undo')
                ),
                Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(context: context, barrierDismissible: false,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Restart Game?'),
                          content: Text('Please confirm whether you want to restart the game.\nYour score is ${context.read<MyGameState>().score} and are ${context.read<MyGameState>().moveNum} moves in.'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('Go back')),
                              TextButton(
                              onPressed: () {
                                context.read<MyGameState>().setUp();
                                Navigator.of(context).pop();
                              },
                              child: const Text('Restart'))
                          ]
                        );
                      }
                    );
                  },
                  icon: Icon(Icons.delete),
                  label: Text('Restart')
                ),
              ],
            )
          ],
      ));})
    )
    );
  }
}

class RadialPainter extends CustomPainter {
  late List<List<int>> grid;
  late List<int> wallPoses;

  RadialPainter({required List<List<int>> gameGrid, required List<int> wallPoses, required Listenable repaint})
    : grid = gameGrid, this.wallPoses = wallPoses,
      super(repaint:repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Set up the painting
    var center = size/2;
    // TODO: CHANGE COLOR BASED OFF NUMBER
    var paint = Paint()
    ..color = Colors.deepOrange
    ..strokeWidth = 20.0
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 3.0);

    // Set up the text
    final textStyle = TextStyle(
      color: Colors.blueGrey,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      height: 1.0
    );
    var numText;

    // TODO: Colour code the shapes based off the number
    // Draw the inner circle with arcs
    var xAdj = 1;
    var yAdj = 1;
    for (var i = 1; i < 5; i++) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(center.width + xAdj*size.width/130, center.height + yAdj*size.height/130), width: size.width/5, height: size.height/5),
        (pi/2)*(i-1),
        pi/2,
        true,
        paint
      );
      numText = TextPainter(
          text: TextSpan(text: grid[0][i-1] != 0 ? '${grid[0][i-1]}' : '  ', style: textStyle),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr
        );
      numText.layout(minWidth: 0, maxWidth: double.infinity);
      numText.paint(canvas, Offset(center.width + (size.width/20) * cos(((pi/2)*(i-1) + (pi/4))) - numText.width/2, center.height + (size.width/20) * sin(((pi/2)*(i-1) + (pi/4))) - numText.height/2));
      if (i%2 == 0) {yAdj = yAdj*-1;} else {xAdj = xAdj*-1;}
    }
    // Draw 3 outer layers of annular sectors
    var layerAdjustment = size.width/30;
    xAdj = -1;
    yAdj = -1;

    // Store positions of text for later painting
    var texts = <Offset, String>{};
    for (var i = 1; i < 4; i++) {
      for (var j = 1; j < 5; j++) {
        if (j%2 == 0) {yAdj = yAdj*-1;} else {xAdj = xAdj*-1;}
        var path = Path();
        // Draw inner arc
        path.arcTo(
          Rect.fromCircle(center: Offset(center.width, center.height), radius: layerAdjustment+size.width/10),
          (pi/2)*(j-1),
          -(pi/2),
          false
        );
        // Draw outer arc
        path.arcTo(
          Rect.fromCircle(center: Offset(center.width, center.height), radius: size.width/10+layerAdjustment+size.width/10),
          (pi/2)*(j-1)-(pi/2),
          (pi/2),
          false
        );
        // Connect the arcs and fill the shape
        path.close();
        // Shift the shape and draw it onto the canvas
        var copyPath = path.shift(Offset(size.width/130*xAdj, size.width/130*yAdj));
        canvas.drawPath(copyPath, paint);
        
        // Store the text and its position
        texts[Offset(center.width + (size.width/20+layerAdjustment+size.width/10) * cos(((pi/2)*(j-1) + (pi/4))) - numText.width/2, center.height + (size.width/20+layerAdjustment+size.width/10) * sin(((pi/2)*(j-1) + (pi/4))) - numText.height/2)] = grid[i][j-1] != 0 ? '${grid[i][j-1]}' : '  ';
      }
      layerAdjustment += size.width/30+size.width/10;
    }

    // Paint the walls onto the correct locations
    for (final (index, wallPose) in wallPoses.indexed) {
      var wallPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = size.width/120
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 0.5);

      switch (wallPose) {
        case 0:
          double x = size.width/130 + (size.width/30+size.width/10) * (index);
          canvas.drawLine(Offset(center.width + x, center.width), Offset(center.width + x + size.width/10, center.width), wallPaint);
          break;
        case 2:
          double x = size.width/130 + (size.width/30+size.width/10) * (index);
          canvas.drawLine(Offset(center.width - x, center.width), Offset(center.width - x - size.width/10, center.width), wallPaint);
          break;
        case 1:
          double y = size.width/130 + (size.width/30+size.width/10) * (index);
          canvas.drawLine(Offset(center.width, center.width + y), Offset(center.width, center.width + y + size.width/10), wallPaint);
          break;
        case 3:
          double y = size.width/130 + (size.width/30+size.width/10) * (index);
          canvas.drawLine(Offset(center.width, center.width - y), Offset(center.width, center.width - y - size.width/10), wallPaint);
          break;
      }
      
    }
    

    // Paint the texts over the shape
    for (var entry in texts.entries) {
      if (entry.value != "0") {
        numText = TextPainter(
          text: TextSpan(text: entry.value, style: textStyle),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr
        )..layout(minWidth: 0, maxWidth: double.infinity);
        numText.paint(canvas, entry.key);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class LeaderboardPage extends StatelessWidget {


  @override
  Widget build(BuildContext context) {
    final leaderboard = context.watch<MyGameState>().leaderboard;
    final TextEditingController textController = TextEditingController();
    return LayoutBuilder(builder: (context, constraints) {
      return Padding(padding: EdgeInsets.all(constraints.biggest.shortestSide*0.02), child: Center(child: 
      Column(children: 
        [Row(children: [
          ElevatedButton.icon(onPressed: () => showDialog(context: context, barrierDismissible: true, builder: (BuildContext context) {
            return AlertDialog(title: Text('Upload your score!'), content: Text('Submit your username and score to the leaderboard, the top 100 are public for everyone!\n If you chose to, you can enter nothing and you will be anonymous'), actions: <Widget>[
              TextField(
                controller: textController,
                decoration: InputDecoration(hintText: "Enter your chosen username: "),
                onSubmitted: (value) {
                  context.read<MyGameState>().submitScore(value);
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text('Submit'),
                onPressed: () {
                  context.read<MyGameState>().submitScore(textController.text);
                  context.read<MyGameState>().setUp(); // Stat new game after submitting this one
                  context.read<MyGameState>().refreshLeaderboard();
                  Navigator.of(context).pop();
                }),
              TextButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                })
            ]);
          }), label: Text('Submit Score'), icon: Icon(Icons.save)),
          Spacer(),
          Text("Check out the top scores! Can you beat them?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          Spacer(),
          ElevatedButton.icon(onPressed: () => context.read()<MyGameState>().refreshLeaderboard(), icon: Icon(Icons.refresh), label: Text("Refresh"))
        ],),
        SizedBox(height: constraints.biggest.shortestSide*0.03),
          Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth*0.95), child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.deepOrangeAccent, width: 2), borderRadius: BorderRadius.circular(8)), 
            child: DataTable(
              columns: const [
                DataColumn(label: Expanded(child: Text('Rank', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))),
                DataColumn(label: Expanded(child: Text('Username', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))),
                DataColumn(label: Expanded(child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))),
                DataColumn(label: Expanded(child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))),
              ],
              rows: List.generate(leaderboard.length, (index) {
                final score = leaderboard[index];
                return DataRow(cells: [
                  DataCell(Text((index + 1).toString())), // Rank
                  DataCell(Text(score['Username'].toString())),
                  DataCell(Text(score['Score'].toString())),
                  DataCell(Text(score['Date'].toString())),
                  ]);
                }),
              ),
            ),
          ))))]
        )));});
    }
  }

class ExpandedSection extends StatelessWidget {
  final Widget child;
  const ExpandedSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: child);
  }
}

class StatusOverlay {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required IconData icon,
    required String message,
    required Rect targetRect, // Position info of your widget
  }) {
    // Remove old overlay
    _currentEntry?.remove();

    final overlay = Overlay.of(context);

    // Create an animation controller
    final animationController = AnimationController(
      vsync: overlay!, // needs TickerProvider, handled by OverlayState
      duration: const Duration(milliseconds: 250),
    );

    final fadeAnimation = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
    );

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: targetRect.center.dy - 20, // Center vertically over widget
        left: targetRect.center.dx - 60, // Roughly center horizontally
        child: Material(
          color: Colors.transparent,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.1),
                end: Offset.zero,
              ).animate(fadeAnimation),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;

    // Start animation
    animationController.forward();

    // Auto-hide
    Future.delayed(const Duration(milliseconds: 800), () async {
      await animationController.reverse();
      entry.remove();
      _currentEntry = null;
    });
  }
}
