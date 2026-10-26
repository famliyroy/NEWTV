import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStore {
  SearchHistoryStore(this._preferences);

  static const _key = 'newtv.search.history';
  final SharedPreferences _preferences;

  List<String> load() => _preferences.getStringList(_key) ?? const [];

  Future<void> add(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final values = [normalized, ...load().where((item) => item != normalized)];
    await _preferences.setStringList(_key, values.take(20).toList());
  }

  Future<void> remove(String query) async {
    await _preferences.setStringList(
      _key,
      load().where((item) => item != query).toList(),
    );
  }

  Future<void> clear() => _preferences.remove(_key);
}
