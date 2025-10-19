import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math';

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
  late List<List<int>> grid;
  var empty = [];
  int maxNum = 0;
  //TODO: TRACK THE HIGHEST NUMBER!
  late List<List<int>> lastMove;
  List<int> wallPoses = [];
  int moveNum = 0;
  var undid = false;
  var shouldRepaint = false;
  var leaderboard = List.generate(10, (i) => random.nextInt(100));
  
  void setUp() {
    grid = List.generate(4, (i) => List.generate(4, (j) => 0));
    lastMove = List.from(grid);
    moveNum = 0;
    maxNum = 0;
    // Keep track of empties
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        empty.add([row, col]);
      }
    }
    wallPoses = List.generate(4, (i) => random.nextInt(4));
    makeNewTile();
    makeNewTile();
    notifyListeners();
  }

  void makeNewTile() {
    // Find a random empty space on the grid
    var tilePos = empty[random.nextInt(empty.length)];
    empty.remove(tilePos);
    // Produce a new number with a 10% of being a 4 and a 90% chance of being a 2
    int newValue = random.nextInt(10) == 0 ? 4 : 2;
    grid[tilePos[0]][tilePos[1]] = newValue;
    if (newValue > maxNum) maxNum = newValue;
  }

  void doMove(Move movement) {
    lastMove = List.from(grid);
    switch (movement) {
      case Move.antiClockwise:
        // Repeat this for all of the rows
        for (var i = 0; i < 4; i++) {
          // Keep track of the next spot to fill
          var nextPos = 3;
          for (var j = 3; j > -1; j--) { // Loop through the cells in the row
            if (grid[i][j] != 0) { // If the cell is not empty
              // If the next cell exists and is equal to this one
              if (j > 0 && grid[i][j-1] == grid[j][i]) {
                int newValue = grid[i][j]*2;
                grid[i][nextPos] = newValue;
                grid[i][j-1] = 0;
                empty.add([i, j-1]);
                if (newValue > maxNum) maxNum = newValue;
              }
              else {
                grid[i][nextPos] = grid[i][j];
              }
              // Clear the cells if something has been moved
              if (nextPos != j) {
                grid[i][j] = 0;
                empty.add([i, j]);
                empty.remove([i, nextPos]);
              }
              // ^ Fill up the next position cell as required
              nextPos -= 1; // Increment the next available position
            }
          }
        }
        break;
      case Move.clockwise:
        // Repeat this for all of the rows
        for (var i = 0; i < 4; i++) {
          // Keep track of the next spot to fill
          var nextPos = 0;
          for (var j = 0; j < 4; j++) { // Loop through the cells in the row
            if (grid[i][j] != 0) { // If the cell is not empty
              // If the next cell exists and is equal to this one
              if (j < 3 && grid[i][j+1] == grid[j][i]) {
                int newValue = grid[i][j]*2;
                grid[i][nextPos] = newValue;
                grid[i][j+1] = 0;
                empty.add([i, j+1]);
                if (newValue > maxNum) maxNum = newValue;
              }
              else {
                grid[i][nextPos] = grid[i][j];
              }
              // Clear the cells if something has been moved
              if (nextPos != j) {
                grid[i][j] = 0;
                empty.add([i, j]);
                empty.remove([i, nextPos]);
              }
              // ^ Fill up the next position cell as required
              nextPos += 1; // Increment the next available position
            }
          }
        }
        break;
      case Move.inwards:
        // Repeat this for all of the columns
        for (var i = 0; i < 4; i++) {
          var nextPos = 0; // Keep track of the next spot to fill
          for (var j = 0; j < 4; j++) { // Loop through the cells in the column
            if (grid[j][i] != 0) { // If the cell is not empty
              // If the next cell exists and is equal to this one
              if (j < 3 && grid[j+1][i] == grid[j][i]) {
                int newValue = grid[j][i]*2;
                grid[nextPos][i] = newValue;
                grid[j+1][i] = 0;
                empty.add([j+1, i]);
                if (newValue > maxNum) maxNum = newValue;
              }
              else {
                grid[nextPos][i] = grid[j][i];
              }
              // Clear the cells if something has been moved
              if (nextPos != j) {
                grid[j][i] = 0;
                empty.add([j, i]);
                empty.remove([nextPos, i]);
              }
              // ^ Fill up the next position cell as required
              nextPos += 1; // Increment the next available position
            }
          }
        }
        break;
      case Move.outwards:
        // Repeat this for all of the columns
        for (var i = 0; i < 4; i++) {
          var nextPos = 3; // Keep track of the next spot to fill
          for (var j = 3; j > -1; j--) { // Loop through the cells in the column
            if (grid[j][i] != 0) { // If the cell is not empty
              // If the next cell exists and is equal to this one
              if (j > 0 && grid[j-1][i] == grid[j][i]) {
                int newValue = grid[j][i]*2;
                grid[nextPos][i] = newValue;
                grid[j-1][i] = 0;
                empty.add([j-1, i]);
                if (newValue > maxNum) maxNum = newValue;
              }
              else {
                grid[nextPos][i] = grid[j][i];
              }
              // Clear the cells if something has been moved
              if (nextPos != j) {
                grid[j][i] = 0;
                empty.add([j, i]);
                empty.remove([nextPos, i]);
              }
              // ^ Fill up the next position cell as required
              nextPos -= 1; // Increment the next available position
            }
          }
        }
    }
    moveNum += 1;
    undid = false;
    makeNewTile();
    shouldRepaint = true;
    debugPrint('a move has actually been done');
    notifyListeners();
  }

  void undo() {
    grid = List.from(lastMove);
    moveNum -= 1;
    undid = true;
    notifyListeners();
  }
  
  void recordGame(String username, int maxNum) {
    // TODO: code stuff to record the game
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
          debugPrint('Outwards');
          break;
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.keyS:
          debugPrint('Inwards');
          context.read<MyGameState>().doMove(Move.inwards);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.inwards); repaintNotifier.value++;});
          debugPrint('Inwards');
          break;
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.keyD:
          debugPrint('Clockwise');
          context.read<MyGameState>().doMove(Move.clockwise);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.clockwise); repaintNotifier.value++;});
          debugPrint('Clockwise');
          break;
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.keyA:
          debugPrint('Anticlockwise');
          context.read<MyGameState>().doMove(Move.antiClockwise);
          repaintNotifier.value++;
          //WidgetsBinding.instance.addPostFrameCallback((_) {context.read<MyGameState>().doMove(Move.antiClockwise); repaintNotifier.value++;});
          debugPrint('Anticlockwise');
          break;
        default:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    grid = context.watch<MyGameState>().grid;
    wallPoses = context.watch<MyGameState>().wallPoses;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) => _onKeyEvent(event),
      child: Column(
        children: [
          // TODO: add a tutorial question mark button here
          Row(
            children: [
              Text('Move ${context.watch<MyGameState>().moveNum}'),
              Spacer(),
              Text('Highest Number ${context.watch<MyGameState>().maxNum}')
            ],
          ),
          Center(
            child: CustomPaint(painter: RadialPainter(gameGrid: grid, wallPoses: wallPoses, repaint: repaintNotifier), child: SizedBox.square(dimension: 500.0,))
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
                        content: Text('Please confirm whether you want to restart the game.\nYour highest number is ${context.read<MyGameState>().maxNum} and are ${context.read<MyGameState>().moveNum} moves in.'),
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
      )
    );
  }
}

class RadialPainter extends CustomPainter {
  late List<List<int>> grid;
  late List<int> wallPoses;

  RadialPainter({required List<List<int>> gameGrid, required List<int> wallPoses, required Listenable repaint})
    : grid = gameGrid, this.wallPoses = wallPoses,
      super(repaint: repaint);

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
        text: TextSpan(text: '${grid[0][i-1]}', style: textStyle),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr
      );
      numText.layout(minWidth: 0, maxWidth: double.infinity);
      numText.paint(canvas, Offset(center.width - numText.width/2 + xAdj*size.width/22, center.height - numText.height/2 + yAdj*size.height/22));
      if (i%2 == 0) {yAdj = yAdj*-1;} else {xAdj = xAdj*-1;}
    }
    // Draw 3 outer layers of annular sectors
    var layerAdjustment = size.width/20;
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
        texts[Offset(center.width + (size.width/20+layerAdjustment+size.width/10) * sin(((pi/2)*(j-1) + (pi/4))) - numText.width/2, center.height + (size.width/20+layerAdjustment+size.width/10) * cos(((pi/2)*(j-1) + (pi/4))) - numText.height/2)] = '${grid[i][j-1]}';
      }
      layerAdjustment += size.width/20+size.width/10;
    }

    // Paint the walls onto the correct locations
    for (final (index, wallPose) in wallPoses.indexed) {
      var wallPaint = Paint()
        ..color = Colors.black45
        ..strokeWidth = size.width/120
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 0.5);

      switch (wallPose) {
        case 0:
          double x = size.width/130 + (size.width/20+size.width/10) * (index);
          canvas.drawLine(Offset(center.width + x, center.width), Offset(center.width + x + size.width/10, center.width), wallPaint);
          break;
        case 2:
          double x = size.width/130 + (size.width/20+size.width/10) * (index);
          canvas.drawLine(Offset(center.width - x, center.width), Offset(center.width - x - size.width/10, center.width), wallPaint);
          break;
        case 1:
          double y = size.width/130 + (size.width/20+size.width/10) * (index);
          canvas.drawLine(Offset(center.width, center.width + y), Offset(center.width, center.width + y + size.width/10), wallPaint);
          break;
        case 3:
          double y = size.width/130 + (size.width/20+size.width/10) * (index);
          canvas.drawLine(Offset(center.width, center.width - y), Offset(center.width, center.width - y - size.width/10), wallPaint);
          break;
      }
      
    }
    

    // Paint the texts over the shape
    // TODO: do not show the number if it is 0
    for (var entry in texts.entries) {
      // TODO: Don't show text if it's equal to 0
      numText = TextPainter(
          text: TextSpan(text: entry.value, style: textStyle),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr
        )..layout(minWidth: 0, maxWidth: double.infinity);
      numText.paint(canvas, entry.key);
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
    return Center(
      child: Column(
        children: [
          Text('✨Leaderboard✨'),
          ListView(
            children: [
              for (var fav in context.watch<MyGameState>().leaderboard)
                Text("$fav"),
            ],
          ),
        ],
      ),
    );
  }
}