import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const lime = Color(0xFFD4F53C),
    court = Color(0xFF0B7A8F),
    deep = Color(0xFF063B47);
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const levels = ['Beginner', 'Novice', 'Intermediate', 'Advanced'];
const startingRatings = [1000.0, 1100.0, 1200.0, 1400.0];

class Player {
  int? id;
  String name, skillLevel;
  double rating;
  int games, wins, losses;
  int? queuedAt;
  Player(
      {this.id,
      required this.name,
      this.skillLevel = 'Beginner',
      this.rating = 1000,
      this.games = 0,
      this.wins = 0,
      this.losses = 0,
      this.queuedAt});
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'skill_level': skillLevel,
        'rating': rating,
        'games': games,
        'wins': wins,
        'losses': losses,
        'queued_at': queuedAt
      };
  factory Player.from(Map m) => Player(
      id: m['id'],
      name: m['name'],
      skillLevel:
          levels.contains(m['skill_level']) ? m['skill_level'] : 'Beginner',
      rating: (m['rating'] as num).toDouble(),
      games: m['games'],
      wins: m['wins'],
      losses: m['losses'],
      queuedAt: m['queued_at']);
  double get winPct => games == 0 ? 0 : wins / games * 100;
}

class Pairing {
  final List<Player> a, b;
  Pairing(this.a, this.b);
  List<Player> get all => [...a, ...b];
}

class CourtMatch {
  final int courtNumber;
  final Pairing pairing;
  final bool doubles;
  final int target;
  CourtMatch(this.courtNumber, this.pairing, this.doubles, this.target);
}

class ActiveCourtMatch {
  final CourtMatch match;
  ActiveCourtMatch(this.match);
}

class Game {
  final bool dbl;
  final int target;
  List<int> pts = [0, 0];
  int serving;
  int server;
  final List<List<int>> hist = [];
  Game(this.dbl, this.target, this.serving) : server = dbl ? 2 : 1;
  void _snap() => hist.add([pts[0], pts[1], serving, server]);
  void undo() {
    if (hist.isEmpty) return;
    final h = hist.removeLast();
    pts = [h[0], h[1]];
    serving = h[2];
    server = h[3];
  }

  void servePoint() {
    _snap();
    pts[serving]++;
  }

  void faultOrSideOut() {
    _snap();
    if (dbl && server == 1) {
      server = 2;
    } else {
      serving = 1 - serving;
      server = 1;
    }
  }

  bool get over =>
      (pts[0] >= target || pts[1] >= target) && (pts[0] - pts[1]).abs() >= 2;
  int get winner => pts[0] > pts[1] ? 0 : 1;
  String get call => dbl
      ? '${pts[serving]}-${pts[1 - serving]}-$server'
      : '${pts[serving]}-${pts[1 - serving]}';
  String get side => pts[serving] % 2 == 0 ? 'right (even)' : 'left (odd)';
}

class DB {
  static Database? _d;
  static Future<Database> get db async => _d ??= await openDatabase(
          p.join(await getDatabasesPath(), 'picklematch.db'),
          version: 2, onCreate: (d, v) async {
        await d.execute(
            "CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,skill_level TEXT NOT NULL DEFAULT 'Beginner',rating REAL NOT NULL,games INTEGER NOT NULL,wins INTEGER NOT NULL,losses INTEGER NOT NULL,queued_at INTEGER)");
        await d.execute(
            'CREATE TABLE matches(id INTEGER PRIMARY KEY AUTOINCREMENT,played_at TEXT NOT NULL,mode TEXT NOT NULL,target INTEGER NOT NULL,team1 TEXT NOT NULL,team2 TEXT NOT NULL,score1 INTEGER NOT NULL,score2 INTEGER NOT NULL)');
        await d
            .execute('CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT)');
      }, onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute(
              "ALTER TABLE players ADD COLUMN skill_level TEXT NOT NULL DEFAULT 'Beginner'");
          await d.execute(
              "UPDATE players SET skill_level = CASE WHEN rating < 1100 THEN 'Beginner' WHEN rating < 1200 THEN 'Novice' WHEN rating < 1400 THEN 'Intermediate' ELSE 'Advanced' END");
        }
      });
  static Future<List<Player>> players() async =>
      (await (await db).query('players', orderBy: 'name COLLATE NOCASE'))
          .map(Player.from)
          .toList();
  static Future<void> save(Player x) async {
    final d = await db;
    if (x.id == null) {
      x.id = await d.insert('players', x.toMap()..remove('id'));
    } else {
      await d.update('players', x.toMap(), where: 'id=?', whereArgs: [x.id]);
    }
  }

  static Future<void> del(int id) async =>
      (await db).delete('players', where: 'id=?', whereArgs: [id]);
  static Future<void> queue(int id, int? v) async => (await db)
      .update('players', {'queued_at': v}, where: 'id=?', whereArgs: [id]);
  static Future<void> addMatch(String mode, int target, String t1, String t2,
          int s1, int s2) async =>
      (await db).insert('matches', {
        'played_at': DateTime.now().toIso8601String(),
        'mode': mode,
        'target': target,
        'team1': t1,
        'team2': t2,
        'score1': s1,
        'score2': s2
      });
  static Future<List<Map<String, Object?>>> matches() async =>
      (await db).query('matches', orderBy: 'id DESC', limit: 100);
  static Future<void> reset() async {
    final d = await db;
    await d.delete('players');
    await d.delete('matches');
  }

  static Future<String> get(String k, String def) async {
    final r =
        await (await db).query('settings', where: 'key=?', whereArgs: [k]);
    return r.isEmpty ? def : r.first['value'] as String;
  }

  static Future<void> put(String k, String v) async =>
      (await db).insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
}

ThemeData mk(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: court, brightness: b));
void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, m, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PickleMatch',
          themeMode: m,
          theme: mk(Brightness.light),
          darkTheme: mk(Brightness.dark),
          home: const Home()));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Player> players = [];
  List<Map<String, Object?>> hist = [];
  int tab = 0, target = 11, minGames = 5, courtCount = 1;
  bool dbl = true, skill = false, requeue = true;
  String? note;
  String? courtCountError;
  final courtCountController = TextEditingController(text: '1');
  List<CourtMatch> courtMatches = [];
  final List<ActiveCourtMatch> activeMatches = [];
  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    load(first: true);
  }

  @override
  void dispose() {
    courtCountController.dispose();
    super.dispose();
  }

  Future<void> load({bool first = false}) async {
    if (first) {
      final t = await DB.get('theme', 'system');
      themeMode.value = ThemeMode.values
          .firstWhere((m) => m.name == t, orElse: () => ThemeMode.system);
      minGames = int.tryParse(await DB.get('minGames', '5')) ?? 5;
      requeue = (await DB.get('requeue', '1')) == '1';
    }
    final l = await DB.players();
    final h = await DB.matches();
    if (!mounted) return;
    setState(() {
      players = l;
      hist = h;
    });
  }

  List<Player> get queue => players.where((x) => x.queuedAt != null).toList()
    ..sort((a, b) => a.queuedAt!.compareTo(b.queuedAt!));
  String waited(Player x) {
    final m =
        ((DateTime.now().millisecondsSinceEpoch - x.queuedAt!) / 60000).floor();
    return m < 1 ? 'just joined' : 'waiting $m min';
  }

  String names(List<Player> l) => l.map((x) => x.name).join(' & ');
  double avg(List<Player> l) => l.fold(0.0, (s, x) => s + x.rating) / l.length;
  int levelIndex(Player x) => levels.indexOf(x.skillLevel);
  int now() => DateTime.now().millisecondsSinceEpoch;
  int? activeCourtFor(Player player) {
    for (final active in activeMatches) {
      if (active.match.pairing.all.any((x) => x.id == player.id)) {
        return active.match.courtNumber;
      }
    }
    return null;
  }

  Pairing pairPlayers(List<Player> selected) {
    if (!skill) {
      final shuffled = [...selected]..shuffle(Random());
      return Pairing(shuffled.sublist(0, shuffled.length ~/ 2),
          shuffled.sublist(shuffled.length ~/ 2));
    }
    if (!dbl) return Pairing([selected[0]], [selected[1]]);
    List<Player>? best;
    var smallestGap = double.infinity;
    for (var i = 0; i < selected.length; i++) {
      for (var j = i + 1; j < selected.length; j++) {
        final teamA = [selected[i], selected[j]];
        final teamB = selected.where((x) => !teamA.contains(x)).toList();
        final gap = (teamA.fold(0, (sum, x) => sum + levelIndex(x)) -
                teamB.fold(0, (sum, x) => sum + levelIndex(x)))
            .abs()
            .toDouble();
        if (gap < smallestGap) {
          smallestGap = gap;
          best = [...teamA, ...teamB];
        }
      }
    }
    final balanced = best!;
    return Pairing(balanced.sublist(0, 2), balanced.sublist(2));
  }

  void generateMatches() {
    final n = dbl ? 4 : 2;
    final reserved = {
      ...courtMatches.expand((match) => match.pairing.all.map((x) => x.id)),
      ...activeMatches
          .expand((match) => match.match.pairing.all.map((x) => x.id)),
    };
    final waiting = queue.where((x) => !reserved.contains(x.id)).toList();
    final freeCourtCount =
        max(0, courtCount - courtMatches.length - activeMatches.length);
    final count = min(freeCourtCount, waiting.length ~/ n);
    final usedCourts = {
      ...courtMatches.map((match) => match.courtNumber),
      ...activeMatches.map((match) => match.match.courtNumber),
    };
    var nextCourt = 1;
    for (var i = 0; i < count; i++) {
      while (usedCourts.contains(nextCourt)) {
        nextCourt++;
      }
      courtMatches.add(CourtMatch(nextCourt,
          pairPlayers(waiting.sublist(i * n, (i + 1) * n)), dbl, target));
      usedCourts.add(nextCourt++);
    }
  }

  Future<void> editCourtMatch(int index) async {
    final current = courtMatches[index];
    final reservedElsewhere = courtMatches
        .where((match) => match != current)
        .expand((match) => match.pairing.all)
        .map((player) => player.id)
        .toSet();
    final available = queue
        .where((player) => !reservedElsewhere.contains(player.id))
        .toList();
    final selected = [...current.pairing.all];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Widget picker(int slot, String label) {
            return DropdownButtonFormField<int>(
              key: ValueKey('court-edit-$slot-${selected[slot].id}'),
              initialValue: selected[slot].id,
              decoration: InputDecoration(labelText: label),
              items: [
                for (final player in available)
                  DropdownMenuItem(
                      value: player.id!,
                      child: Text('${player.name} - ${player.skillLevel}')),
              ],
              onChanged: (id) {
                if (id == null) return;
                setDialogState(() => selected[slot] =
                    available.firstWhere((player) => player.id == id));
              },
            );
          }

          final teamSize = selected.length ~/ 2;
          return AlertDialog(
            title: Text('Edit Court ${current.courtNumber} teams'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'Select a queued player for each slot. Each player can only be used once.'),
                  for (var slot = 0; slot < selected.length; slot++)
                    picker(slot,
                        'Team ${slot ~/ teamSize + 1}, player ${slot % teamSize + 1}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: selected.map((player) => player.id).toSet().length !=
                        selected.length
                    ? null
                    : () {
                        setState(() {
                          courtMatches[index] = CourtMatch(
                              current.courtNumber,
                              Pairing(selected.take(teamSize).toList(),
                                  selected.skip(teamSize).toList()),
                              current.doubles,
                              current.target);
                        });
                        Navigator.pop(dialogContext);
                      },
                child: const Text('Save teams'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> queueAll() async {
    final l = players
        .where((x) => x.queuedAt == null && activeCourtFor(x) == null)
        .toList()
      ..shuffle(Random());
    var t = now();
    for (final x in l) {
      await DB.queue(x.id!, t++);
    }
    if (mounted) setState(() => courtMatches.clear());
    load();
  }

  Future<void> start(int index) async {
    final match = courtMatches[index];
    for (final q in match.pairing.all) {
      q.queuedAt = null;
      await DB.queue(q.id!, null);
    }
    if (!mounted) return;
    setState(() {
      courtMatches.removeAt(index);
      activeMatches.add(ActiveCourtMatch(match));
    });
  }

  Future<void> recordResult(int index) async {
    final active = activeMatches[index];
    final match = active.match;
    final scoreA = TextEditingController();
    final scoreB = TextEditingController();
    var winner = 0;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Record Court ${match.courtNumber} result'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: winner,
                  decoration: const InputDecoration(labelText: 'Winning team'),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Team 1 - ${names(match.pairing.a)}'),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Team 2 - ${names(match.pairing.b)}'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => winner = value);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: scoreA,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Team 1 score'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('–'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: scoreB,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Team 2 score'),
                      ),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final a = int.tryParse(scoreA.text.trim());
                final b = int.tryParse(scoreB.text.trim());
                if (a == null || b == null || a < 0 || b < 0) {
                  setDialogState(() =>
                      error = 'Enter a non-negative score for both teams.');
                  return;
                }
                if (a == b || (winner == 0 ? a < b : b < a)) {
                  setDialogState(() => error =
                      'The selected winner must have the higher score.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save result'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await finish(
          match, int.parse(scoreA.text.trim()), int.parse(scoreB.text.trim()));
      setState(() => activeMatches.remove(active));
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Match result saved to the leaderboard.')),
        );
      }
    }
    scoreA.dispose();
    scoreB.dispose();
  }

  Future<void> finishWithoutScore(int index) async {
    final active = activeMatches[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text('Finish Court ${active.match.courtNumber} without a result?'),
        content: const Text(
            'This match will not be added to match history or player records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep match')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Finish without score')),
        ],
      ),
    );
    if (confirmed != true) return;
    var queuedAt = now();
    for (final player in active.match.pairing.all) {
      player.queuedAt = requeue ? queuedAt++ : null;
      await DB.save(player);
    }
    if (!mounted) return;
    setState(() => activeMatches.remove(active));
    await load();
  }

  Future<void> finish(CourtMatch match, int s1, int s2) async {
    final x = match.pairing;
    final ra = avg(x.a), rb = avg(x.b);
    final e1 = 1 / (1 + pow(10, (rb - ra) / 400));
    final w1 = s1 > s2;
    for (final q in x.a) {
      q.rating += (q.games < 10 ? 32.0 : 20.0) * ((w1 ? 1 : 0) - e1);
      q.games++;
      if (w1) {
        q.wins++;
      } else {
        q.losses++;
      }
    }
    for (final q in x.b) {
      q.rating += (q.games < 10 ? 32.0 : 20.0) * ((w1 ? 0 : 1) - (1 - e1));
      q.games++;
      if (w1) {
        q.losses++;
      } else {
        q.wins++;
      }
    }
    final order = x.all..shuffle(Random());
    var t = now();
    for (final q in order) {
      if (requeue) {
        q.queuedAt = t++;
      }
      await DB.save(q);
    }
    await DB.addMatch(match.doubles ? 'Doubles' : 'Singles', match.target,
        names(x.a), names(x.b), s1, s2);
  }

  Future<void> editPlayer([Player? pl]) async {
    if (pl != null && activeCourtFor(pl) != null) {
      final playingCourt = activeCourtFor(pl)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${pl.name} is playing on Court $playingCourt.')),
      );
      return;
    }
    final name = TextEditingController(text: pl?.name);
    String? err;
    var changed = false;
    var lvl = pl?.skillLevel ?? 'Beginner';
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pl == null ? 'Add player' : 'Edit player',
                          style: Theme.of(c).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      TextField(
                          controller: name,
                          maxLength: 20,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                              labelText: 'Player name *',
                              errorText: err,
                              border: const OutlineInputBorder())),
                      const Text('Skill level'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final k in levels)
                          ChoiceChip(
                              label: Text(k),
                              selected: lvl == k,
                              onSelected: (_) => set(() => lvl = k))
                      ]),
                      if (pl != null)
                        Text('${pl.games} games, ${pl.wins} wins'),
                      const SizedBox(height: 16),
                      Row(children: [
                        if (pl != null)
                          TextButton.icon(
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                    context: c,
                                    builder: (d) => AlertDialog(
                                            title: Text('Delete ${pl.name}?'),
                                            content: const Text(
                                                'Their skill level and record will be removed.'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(d, false),
                                                  child: const Text('Cancel')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(d, true),
                                                  child: const Text('Delete'))
                                            ]));
                                if (ok == true) {
                                  await DB.del(pl.id!);
                                  changed = true;
                                  if (c.mounted) Navigator.pop(c);
                                }
                              }),
                        const Spacer(),
                        TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        FilledButton(
                            onPressed: () async {
                              final n = name.text.trim();
                              if (n.isEmpty) {
                                set(() => err = 'Please enter a name.');
                                return;
                              }
                              if (players.any((x) =>
                                  x.name.toLowerCase() == n.toLowerCase() &&
                                  x.id != pl?.id)) {
                                set(() => err = 'That name is already used.');
                                return;
                              }
                              if (pl == null) {
                                await DB.save(Player(
                                    name: n,
                                    skillLevel: lvl,
                                    rating:
                                        startingRatings[levels.indexOf(lvl)]));
                              } else {
                                pl.name = n;
                                pl.skillLevel = lvl;
                                await DB.save(pl);
                              }
                              changed = true;
                              if (c.mounted) Navigator.pop(c);
                            },
                            child: Text(pl == null ? 'Add' : 'Save')),
                      ]),
                    ]))));
    if (changed && mounted) setState(() => courtMatches.clear());
    load();
  }

  Widget heroCard(String small, String big, String sub, IconData icon) =>
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [deep, court])),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(small, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(big,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800)),
                  Text(sub,
                      style: const TextStyle(
                          color: lime, fontWeight: FontWeight.w600))
                ])),
            Container(
                width: 64,
                height: 64,
                decoration:
                    const BoxDecoration(color: lime, shape: BoxShape.circle),
                child: Icon(icon, color: deep, size: 34))
          ]));

  Widget courtCard(int index) {
    final match = courtMatches[index];
    final pairing = match.pairing;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Court ${match.courtNumber}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${match.doubles ? 'Doubles' : 'Singles'} to ${match.target}',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('${names(pairing.a)} vs ${names(pairing.b)}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${pairing.a.map((player) => player.skillLevel).join(' & ')} vs ${pairing.b.map((player) => player.skillLevel).join(' & ')}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit teams'),
                    onPressed: () => editCourtMatch(index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start match'),
                    onPressed: () => start(index),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget activeCourtCard(int index) {
    final active = activeMatches[index];
    final match = active.match;
    final pairing = match.pairing;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: cs.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Court ${match.courtNumber} - In progress',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${names(pairing.a)} vs ${names(pairing.b)}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text('Record result'),
                    onPressed: () => recordResult(index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => finishWithoutScore(index),
                    child: const Text('Finish without score'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget playTab() {
    final q = queue, n = dbl ? 4 : 2;
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          heroCard(
              'Open play queue',
              '${q.length} waiting',
              q.length >= n
                  ? '${min(courtCount, q.length ~/ n)} court matches available'
                  : 'Need ${n - q.length} more for ${dbl ? 'doubles' : 'singles'}',
              Icons.sports_tennis),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Singles 1v1'),
                    icon: Icon(Icons.person)),
                ButtonSegment(
                    value: true,
                    label: Text('Doubles 2v2'),
                    icon: Icon(Icons.people))
              ],
              selected: {
                dbl
              },
              onSelectionChanged: (s) => setState(() {
                    dbl = s.first;
                    courtMatches.clear();
                  })),
          const SizedBox(height: 10),
          SegmentedButton<int>(segments: const [
            ButtonSegment(value: 11, label: Text('Play to 11')),
            ButtonSegment(value: 15, label: Text('to 15')),
            ButtonSegment(value: 21, label: Text('to 21'))
          ], selected: {
            target
          }, onSelectionChanged: (s) => setState(() => target = s.first)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                  child: Text('Number of courts',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: courtCountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                      suffixText: 'courts',
                      border: OutlineInputBorder(),
                      isDense: true,
                      errorText: courtCountError),
                  onChanged: (value) {
                    final count = int.tryParse(value);
                    if (count == null || count < 1) {
                      setState(() {
                        courtCountError = 'Enter a whole number above 0.';
                        courtMatches.clear();
                      });
                    } else if (count != courtCount || courtCountError != null) {
                      setState(() {
                        courtCount = count;
                        courtCountError = null;
                        courtMatches.clear();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Match by skill level',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Queue order picks players; teams are balanced by Beginner, Novice, Intermediate, and Advanced levels.'),
            value: skill,
            onChanged: (value) => setState(() {
              skill = value;
              courtMatches.clear();
            }),
          ),
          if (activeMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('IN PROGRESS',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (var i = 0; i < activeMatches.length; i++) activeCourtCard(i),
          ],
          const SizedBox(height: 8),
          Text('UPCOMING MATCHES',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (courtMatches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                activeMatches.length >= courtCount
                    ? 'All courts are in progress. Generate the next matches when a court is free.'
                    : 'No matches scheduled. Generate matches to assign queued players.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < courtMatches.length; i++) courtCard(i),
          const SizedBox(height: 12),
          Row(children: [
            Text('Queue (first in, first played)',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
                onPressed: players.isEmpty ? null : queueAll,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Queue everyone'))
          ]),
          if (q.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text(
                        'Nobody is in the queue. Add players in the Players tab.'))),
          for (var i = 0; i < q.length; i++)
            TweenAnimationBuilder<double>(
                key: ValueKey('q${q[i].id}'),
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 250 + i * 40),
                builder: (_, v, c) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                        offset: Offset(0, 14 * (1 - v)), child: c)),
                child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: courtMatches
                            .expand((match) => match.pairing.all)
                            .any((player) => player.id == q[i].id)
                        ? cs.secondaryContainer
                        : cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor: i < n ? cs.primary : cs.outline,
                            foregroundColor: cs.onPrimary,
                            child: Text('${i + 1}')),
                        title: Text(q[i].name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${q[i].skillLevel} - ${waited(q[i])}'),
                        trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove from queue',
                            onPressed: () async {
                              await DB.queue(q[i].id!, null);
                              if (mounted) {
                                setState(() => courtMatches.clear());
                              }
                              load();
                            })))),
        ]);
  }

  Widget playersTab() => players.isEmpty
      ? const Center(
          child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No players yet. Tap Add player to start.',
                  textAlign: TextAlign.center)))
      : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
          for (var i = 0; i < players.length; i++)
            TweenAnimationBuilder<double>(
                key: ValueKey('p${players[i].id}'),
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 250 + i * 40),
                builder: (_, v, c) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                        offset: Offset(0, 14 * (1 - v)), child: c)),
                child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    child: ListTile(
                        onTap: () => editPlayer(players[i]),
                        leading: CircleAvatar(
                            backgroundColor: lime,
                            foregroundColor: deep,
                            child: Text(players[i].name[0].toUpperCase(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900))),
                        title: Text(players[i].name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${players[i].skillLevel} - ${players[i].wins}W ${players[i].losses}L'),
                        trailing: IconButton(
                            tooltip: activeCourtFor(players[i]) != null
                                ? 'Playing on Court ${activeCourtFor(players[i])}'
                                : players[i].queuedAt == null
                                    ? 'Join queue'
                                    : 'Leave queue',
                            icon: Icon(
                                activeCourtFor(players[i]) != null
                                    ? Icons.sports_tennis
                                    : players[i].queuedAt == null
                                        ? Icons.playlist_add
                                        : Icons.check_circle,
                                color: activeCourtFor(players[i]) != null
                                    ? cs.secondary
                                    : players[i].queuedAt == null
                                        ? null
                                        : cs.primary),
                            onPressed: activeCourtFor(players[i]) != null
                                ? null
                                : () async {
                                    await DB.queue(
                                        players[i].id!,
                                        players[i].queuedAt == null
                                            ? now()
                                            : null);
                                    if (mounted) {
                                      setState(() => courtMatches.clear());
                                    }
                                    load();
                                  })))),
        ]);

  Widget rankTab() {
    final ranked = players.where((x) => x.games >= minGames).toList()
      ..sort((a, b) {
        final c = b.rating.compareTo(a.rating);
        if (c != 0) return c;
        final w = b.winPct.compareTo(a.winPct);
        return w != 0 ? w : b.games.compareTo(a.games);
      });
    final prov = players.where((x) => x.games < minGames).toList()
      ..sort((a, b) => b.games.compareTo(a.games));
    final medal = [
      const Color(0xFFFFC107),
      const Color(0xFFB0BEC5),
      const Color(0xFFCD7F32)
    ];
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          heroCard(
              'Leaderboard',
              ranked.isEmpty ? 'No ranks yet' : ranked.first.name,
              'Ranked after $minGames games',
              Icons.emoji_events),
          const SizedBox(height: 8),
          Text(
              'Rankings are based on match performance, with win rate and games played as tie-breakers.',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (var i = 0; i < ranked.length; i++)
            Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: ListTile(
                    leading: i < 3
                        ? Icon(Icons.emoji_events, color: medal[i], size: 34)
                        : CircleAvatar(child: Text('${i + 1}')),
                    title: Text('${i + 1}. ${ranked[i].name}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${ranked[i].skillLevel} - ${ranked[i].wins}W ${ranked[i].losses}L - ${ranked[i].winPct.round()}% wins'))),
          if (prov.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Not ranked yet (needs $minGames games)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final x in prov)
              Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: ListTile(
                      title: Text(x.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                    value: x.games / minGames,
                                    borderRadius: BorderRadius.circular(8)),
                                const SizedBox(height: 4),
                                Text(
                                    '${x.games}/$minGames games - ${minGames - x.games} more to qualify')
                              ])),
                      trailing: Text(x.skillLevel,
                          style: TextStyle(color: cs.onSurfaceVariant)))),
          ],
        ]);
  }

  Widget historyTab() => hist.isEmpty
      ? const Center(child: Text('No matches yet.'))
      : ListView(padding: const EdgeInsets.all(16), children: [
          for (final m in hist)
            Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                child: ListTile(
                    title: Text(
                        '${m['team1']}  ${m['score1']} - ${m['score2']}  ${m['team2']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${m['mode']} to ${m['target']} - ${DateFormat('MMM d, h:mm a').format(DateTime.parse(m['played_at'] as String))}'),
                    trailing: Icon(Icons.sports_score, color: cs.primary)))
        ]);

  Widget settingsTab() =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Text('Theme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode)),
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.phone_android))
            ],
            selected: {
              themeMode.value
            },
            onSelectionChanged: (s) {
              themeMode.value = s.first;
              DB.put('theme', s.first.name);
              setState(() {});
            }),
        const SizedBox(height: 24),
        Text('Minimum games for the leaderboard: $minGames',
            style: Theme.of(context).textTheme.titleMedium),
        Slider(
            value: minGames.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            label: '$minGames',
            onChanged: (v) => setState(() => minGames = v.round()),
            onChangeEnd: (v) => DB.put('minGames', '${v.round()}')),
        const Text(
            'Players need this many completed games before they appear in the ranking. This keeps lucky streaks from topping the board.'),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Re-queue players after a match'),
            subtitle: const Text(
                'Players join the back of the queue so everyone gets turns.'),
            value: requeue,
            onChanged: (v) {
              setState(() => requeue = v);
              DB.put('requeue', v ? '1' : '0');
            }),
        const SizedBox(height: 8),
        Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: const ExpansionTile(
                title: Text('Pickleball rules used',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '- Games go to 11 (or 15 / 21) and must be won by 2 points.'),
                  SizedBox(height: 6),
                  Text(
                      '- Only the serving side can score a point. If the receiving side wins the rally, there is no point.'),
                  SizedBox(height: 6),
                  Text(
                      '- Doubles score is called as: server score - receiver score - server number (1 or 2). The first serving team starts at 0-0-2.'),
                  SizedBox(height: 6),
                  Text(
                      '- Doubles fault: Server 1 passes the serve to Server 2. A fault by Server 2 is a side out, and the new serving team starts with Server 1.'),
                  SizedBox(height: 6),
                  Text(
                      '- Singles score is two numbers (server - receiver). A side out follows every fault.'),
                  SizedBox(height: 6),
                  Text(
                      '- The server serves from the right court when their score is even and the left court when it is odd.')
                ])),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Reset all data'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                          title: const Text('Reset all data?'),
                          content: const Text(
                              'All players, skill levels and match history will be deleted. This cannot be undone.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('Reset'))
                          ]));
              if (ok == true) {
                await DB.reset();
                setState(() {
                  courtMatches.clear();
                  activeMatches.clear();
                });
                load();
              }
            }),
        const SizedBox(height: 16),
        Center(
            child: Image.asset('assets/picklematch-logo.jpg',
                width: 320, height: 175, fit: BoxFit.contain)),
        Center(
            child: Text('PickleMatch v1.0\nData is stored only on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant))),
      ]);

  @override
  Widget build(BuildContext context) {
    const titles = [
      'PickleMatch',
      'Players',
      'Leaderboard',
      'Match history',
      'Settings'
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/icon.png',
                    width: 36, height: 36, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Text(titles[tab],
                style: const TextStyle(fontWeight: FontWeight.w800))
          ]),
          actions: [
            IconButton(
                tooltip: 'Light / dark mode',
                icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
                onPressed: () {
                  themeMode.value = dark ? ThemeMode.light : ThemeMode.dark;
                  DB.put('theme', themeMode.value.name);
                })
          ]),
      body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
              key: ValueKey(tab),
              child: [
                playTab(),
                playersTab(),
                rankTab(),
                historyTab(),
                settingsTab()
              ][tab])),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.bolt),
              label: const Text('Generate matches'),
              onPressed: courtCountError != null
                  ? null
                  : () {
                      final needed = dbl ? 4 : 2;
                      if (queue.length < needed) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Need at least $needed players in the queue for one court.')));
                        return;
                      }
                      setState(generateMatches);
                      if (courtMatches.length + activeMatches.length <
                          courtCount) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Only ${courtMatches.length + activeMatches.length} of $courtCount courts have players ready.')));
                      }
                    })
          : tab == 1
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add player'),
                  onPressed: () => editPlayer())
              : null,
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.sports_tennis), label: 'Play'),
            NavigationDestination(icon: Icon(Icons.groups), label: 'Players'),
            NavigationDestination(
                icon: Icon(Icons.emoji_events), label: 'Ranking'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings')
          ]),
    );
  }
}

class ScoreScreen extends StatefulWidget {
  final List<Player> a, b;
  final bool dbl;
  final int target;
  final Future<void> Function(int, int) onFinish;
  final Future<void> Function() onAbandon;
  const ScoreScreen(
      {super.key,
      required this.a,
      required this.b,
      required this.dbl,
      required this.target,
      required this.onFinish,
      required this.onAbandon});
  @override
  State<ScoreScreen> createState() => _ScoreState();
}

class _ScoreState extends State<ScoreScreen> {
  late final Game g = Game(widget.dbl, widget.target, Random().nextInt(2));
  late final int first = g.serving;
  bool done = false;
  String tn(int i) =>
      (i == 0 ? widget.a : widget.b).map((x) => x.name).join(' & ');

  void act(void Function() f) {
    if (done) return;
    setState(f);
    if (g.over) {
      done = true;
      Future.microtask(finishDialog);
    }
  }

  Future<void> finishDialog() async {
    final save = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
                icon: const Icon(Icons.emoji_events,
                    size: 40, color: Color(0xFFFFC107)),
                title:
                    Text('${tn(g.winner)} win!', textAlign: TextAlign.center),
                content: Text(
                    'Final score ${g.pts[0]} - ${g.pts[1]}. Player records will be updated.',
                    textAlign: TextAlign.center),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Undo last rally')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Save result'))
                ]));
    if (save == true) {
      await widget.onFinish(g.pts[0], g.pts[1]);
      if (mounted) Navigator.pop(context);
    } else {
      setState(() {
        g.undo();
        done = false;
      });
    }
  }

  Future<void> end() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('End match?'),
                content: const Text(
                    'The result will not be saved. Players return to their place in the queue.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep playing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('End match'))
                ]));
    if (ok == true) {
      await widget.onAbandon();
      if (mounted) Navigator.pop(context);
    }
  }

  Widget team(int i) {
    final cs = Theme.of(context).colorScheme;
    final pl = i == 0 ? widget.a : widget.b;
    final serv = g.serving == i;
    return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: serv ? cs.primaryContainer : cs.surfaceContainerHighest,
            border: Border.all(
                color: serv ? cs.primary : Colors.transparent, width: 3)),
        child: Row(children: [
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('TEAM ${i + 1}',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                for (final x in pl)
                  Text(x.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                for (final x in pl)
                  Text(x.skillLevel,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                if (serv)
                  Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: lime, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          widget.dbl
                              ? 'SERVING - Server ${g.server}'
                              : 'SERVING',
                          style: const TextStyle(
                              color: deep,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)))
              ])),
          AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text('${g.pts[i]}',
                  key: ValueKey('$i-${g.pts[i]}'),
                  style: const TextStyle(
                      fontSize: 84, fontWeight: FontWeight.w900)))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (d, _) {
          if (!d) end();
        },
        child: Scaffold(
            appBar: AppBar(
                title: Text(
                    '${widget.dbl ? 'Doubles' : 'Singles'} to ${widget.target}'),
                leading:
                    IconButton(icon: const Icon(Icons.close), onPressed: end),
                actions: [
                  IconButton(
                      icon: const Icon(Icons.undo),
                      tooltip: 'Undo',
                      onPressed: g.hist.isEmpty || done
                          ? null
                          : () => setState(g.undo))
                ]),
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Expanded(child: team(0)),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(children: [
                        Text('SCORE CALL',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 2,
                                fontSize: 12)),
                        AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(g.call,
                                key: ValueKey(g.call),
                                style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    color: cs.primary,
                                    letterSpacing: 3))),
                        Text(
                            'Team ${g.serving + 1} serves from the ${g.side} court',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if (g.hist.isEmpty)
                          Text('Team ${first + 1} serves first (coin toss)',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12))
                      ])),
                  Expanded(child: team(1)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      icon: const Icon(Icons.add_circle_outline),
                      label:
                          const Text('Serving team won the rally (+1 point)'),
                      onPressed: () => act(g.servePoint)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(widget.dbl && g.server == 1
                          ? 'Serving team lost the rally (Server 2 serves)'
                          : 'Serving team lost the rally (side out)'),
                      onPressed: () => act(g.faultOrSideOut)),
                ]))));
  }
}
