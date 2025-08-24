import 'dart:io';
import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// These global variables are declared with 'late' because we initialize them
// in main.dart before they are ever used. This is a null-safe approach.
late String clientID;
late FinanceDatabase database;
late SharedPreferences sharedPreferences;
final uuid = Uuid();

// This function constructs the database instance.
// It's called from your main.dart file during app startup.
FinanceDatabase constructDb({String dbName = 'db'}) {
  final db = LazyDatabase(() async {
    // Get the folder where the app can store data.
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, '$dbName.sqlite'));

    // Use a NativeDatabase connection. This works on iOS, Android, macOS, Windows, and Linux.
    return NativeDatabase(file);
  });
  return FinanceDatabase(db);
}
