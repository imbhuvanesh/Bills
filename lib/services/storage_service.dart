import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();

  factory StorageService() => _instance;

  StorageService._internal();

  SharedPreferences? _prefs;

  static const _billsKey = 'bills_v1';

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Map<String, dynamic>>> loadBills() async {
    await init();
    final jsonString = _prefs!.getString(_billsKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBills(List<Map<String, dynamic>> bills) async {
    await init();
    final encoded = json.encode(bills);
    await _prefs!.setString(_billsKey, encoded);
  }

  Future<void> deleteBill(Map<String, dynamic> bill) async {
    final storedBills = await loadBills();
    final index = storedBills.indexWhere(
      (storedBill) =>
          storedBill['title'] == bill['title'] &&
          storedBill['dueDate'] == bill['dueDate'] &&
          storedBill['amount'] == bill['amount'] &&
          storedBill['description'] == bill['description'],
    );

    if (index == -1) {
      return;
    }

    storedBills.removeAt(index);
    await saveBills(storedBills);
  }
}
