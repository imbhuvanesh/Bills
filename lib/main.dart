import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bills/services/storage_service.dart';
import 'package:bills/services/notification_service.dart';
import 'package:bills/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService().init();
  await NotificationService().init();

  runApp(const BillsApp());
}

// ============================================================
// APP
// ============================================================

class BillsApp extends StatelessWidget {
  const BillsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bills',

      theme: AppTheme.theme,
      home: const HomeScreen(),
    );
  }
}

// ============================================================
// BILL MODEL
// ============================================================

class Bill {
  String title;
  String description;
  double amount;
  DateTime dueDate;
  int iconCodePoint;
  bool reminderEnabled;
  bool isCompleted;
  int reminderHour;
  int reminderMinute;

  Bill({
    required this.title,
    required this.description,
    required this.amount,
    required this.dueDate,
    required this.iconCodePoint,
    this.reminderEnabled = false,
    this.isCompleted = false,
    this.reminderHour = 0,
    this.reminderMinute = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'amount': amount,
      'dueDate': dueDate.toIso8601String(),
      'iconCodePoint': iconCodePoint,
      'reminderEnabled': reminderEnabled,
      'isCompleted': isCompleted,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
    };
  }

  static Bill fromMap(Map<String, dynamic> m) {
    return Bill(
      title: m['title'] as String,
      description: m['description'] as String,
      amount: (m['amount'] as num).toDouble(),
      dueDate: DateTime.parse(m['dueDate'] as String),
      iconCodePoint: m['iconCodePoint'] as int,
      reminderEnabled: m['reminderEnabled'] as bool? ?? false,
      isCompleted: m['isCompleted'] as bool? ?? false,
      reminderHour: m['reminderHour'] as int? ?? 0,
      reminderMinute: m['reminderMinute'] as int? ?? 0,
    );
  }
}

bool matchesDateFilter(DateTime billDate, DateTime? selectedDate) {
  if (selectedDate == null) {
    return true;
  }

  final billDay = DateTime(billDate.year, billDate.month, billDate.day);
  final pickedDay = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );

  return billDay == pickedDay;
}

bool matchesBillSearch(Bill bill, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }

  return bill.title.toLowerCase().contains(normalizedQuery) ||
      bill.description.toLowerCase().contains(normalizedQuery);
}

String cleanAmountInput(String value) => value.replaceAll(',', '').trim();

double? parseAmountInput(String value) {
  final cleaned = cleanAmountInput(value);
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}

String formatCurrency(double value) {
  final normalized = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  final parts = normalized.split('.');
  final integer = parts.first;
  final decimals = parts.length > 1 ? '.${parts[1]}' : '';
  final digits = integer.split('').reversed.toList();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }

  final reverse = buffer.toString().split('').reversed.join();
  return '$reverse$decimals';
}

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final List<Bill> bills = [];
  final TextEditingController searchController = TextEditingController();
  DateTime? selectedDateFilter;

  List<Bill> get filteredBills {
    return bills
        .where(
          (bill) =>
              matchesDateFilter(bill.dueDate, selectedDateFilter) &&
              matchesBillSearch(bill, searchController.text),
        )
        .toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processPendingAlarmCompletions();
    }
  }

  Future<void> _openSupportEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'iambhuvanesh.a@gmail.com',
      queryParameters: {'subject': 'Support request - Bills app'},
    );

    try {
      await launchUrl(emailUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().onTurnOff = _handleAlarmTurnOff;
    _loadBills();
  }

  void _handleAlarmTurnOff(int alarmId) {
    if (!mounted) return;
    final billIndex = bills.indexWhere(
      (bill) =>
          !bill.isCompleted &&
          NotificationService.buildReminderId(bill.title, bill.dueDate) ==
              alarmId,
    );
    if (billIndex == -1) return;
    setState(() {
      bills[billIndex].isCompleted = true;
    });
    _saveAllBills();
  }

  Future<void> _loadBills() async {
    final saved = await StorageService().loadBills();
    if (saved.isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      bills.addAll(saved.map(Bill.fromMap));
    });

    await _processPendingAlarmCompletions();
  }

  Future<void> _processPendingAlarmCompletions() async {
    final ns = NotificationService();
    final stoppedIds = ns.consumeStoppedAlarmIds();
    final activeIds = ns.getActiveAlarmIds();

    if (bills.isEmpty) return;

    var changed = false;
    for (final bill in bills) {
      if (bill.isCompleted || !bill.reminderEnabled) continue;

      final reminderId =
          NotificationService.buildReminderId(bill.title, bill.dueDate);

      final wasStopped = stoppedIds.contains(reminderId);
      final notScheduled = !activeIds.contains(reminderId);

      if (wasStopped || notScheduled) {
        bill.isCompleted = true;
        changed = true;
      }
    }

    if (!changed) return;
    if (mounted) setState(() {});
    await _saveAllBills();
  }

  Future<void> _saveAllBills() async {
    final maps = bills.map((b) => b.toMap()).toList();
    await StorageService().saveBills(maps);
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select a date',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF111111),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      selectedDateFilter = picked;
    });
  }

  Future<void> openAddBillPage({Bill? billToEdit}) async {
    final Bill? newBill = await Navigator.push<Bill>(
      context,
      MaterialPageRoute(
        builder: (context) => AddBillScreen(initialBill: billToEdit),
      ),
    );

    if (newBill == null) {
      return;
    }

    if (billToEdit != null) {
      final index = bills.indexWhere(
        (existing) =>
            existing.title == billToEdit.title &&
            existing.dueDate.isAtSameMomentAs(billToEdit.dueDate),
      );

      if (index != -1) {
        setState(() {
          bills[index] = newBill;
        });
      }
    } else {
      setState(() {
        bills.add(newBill);
      });
    }

    final oldReminderId = billToEdit == null
        ? null
        : NotificationService.buildReminderId(
            billToEdit.title,
            billToEdit.dueDate,
          );
    final newReminderId = NotificationService.buildReminderId(
      newBill.title,
      newBill.dueDate,
    );

    if (oldReminderId != null && oldReminderId != newReminderId) {
      await NotificationService().cancel(oldReminderId);
    }

    if (newBill.reminderEnabled) {
      await NotificationService().scheduleReminder(
        id: newReminderId,
        title: 'Bill due: ${newBill.title}',
        body: '${newBill.description} — ₹${formatCurrency(newBill.amount)}',
        scheduledDate: DateTime(
          newBill.dueDate.year,
          newBill.dueDate.month,
          newBill.dueDate.day,
          newBill.reminderHour,
          newBill.reminderMinute,
        ),
      );
    } else if (oldReminderId != null && oldReminderId == newReminderId) {
      await NotificationService().cancel(newReminderId);
    }

    await _saveAllBills();
  }

  Future<void> deleteBill(Bill bill) async {
    final index = bills.indexOf(bill);
    if (index == -1) return;

    setState(() {
      bills.removeAt(index);
    });

    await _saveAllBills();

    if (bill.reminderEnabled) {
      final reminderId = NotificationService.buildReminderId(
        bill.title,
        bill.dueDate,
      );
      await NotificationService().cancel(reminderId);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bill deleted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  double get totalAmount {
    double total = 0;
    for (final bill in filteredBills) {
      total += bill.amount;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bills',
                              style: GoogleFonts.googleSans(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Keep your payments on track',
                              style: GoogleFonts.googleSans(
                                fontSize: 14,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          '${bills.length} total',
                          style: GoogleFonts.googleSans(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: _pickDateFilter,
                    child: GlassContainer(
                      borderRadius: 18,
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date filter',
                                  style: GoogleFonts.googleSans(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selectedDateFilter == null
                                      ? 'All dates'
                                      : formatFullDate(selectedDateFilter!),
                                  style: GoogleFonts.googleSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selectedDateFilter != null)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => selectedDateFilter = null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Clear',
                                  style: GoogleFonts.googleSans(
                                    fontSize: 11,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white38,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassContainer(
                    borderRadius: 24,
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total selected',
                                style: GoogleFonts.googleSans(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${formatCurrency(totalAmount)}',
                                style: GoogleFonts.googleSans(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${filteredBills.length} ${filteredBills.length == 1 ? 'bill' : 'bills'}',
                            style: GoogleFonts.googleSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Upcoming bills',
                        style: GoogleFonts.googleSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 132,
                        child: TextField(
                          controller: searchController,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.googleSans(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white38,
                              ),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 9,
                            ),
                            hintText: 'Search',
                            hintStyle: GoogleFonts.googleSans(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Colors.white54,
                              size: 17,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 30,
                            ),
                            suffixIcon: searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setState(() {});
                                    },
                                    tooltip: 'Clear search',
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white54,
                                      size: 16,
                                    ),
                                  ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 25,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filteredBills.isEmpty
                      ? EmptyBillsView(onAddBill: () => openAddBillPage())
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                          physics: const BouncingScrollPhysics(),
                          itemCount: filteredBills.length,
                          itemBuilder: (context, index) {
                            final bill = filteredBills[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: BillCard(
                                bill: bill,
                                dueDate: formatDate(bill.dueDate),
                                onReminderChanged: (value) async {
                                  if (value) {
                                    final granted =
                                        await NotificationService()
                                            .requestPermission();
                                    if (!granted && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Notification permission is required for reminders. Please enable it in Settings.',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                  }

                                  setState(() {
                                    bill.reminderEnabled = value;
                                  });

                                  final reminderId =
                                      NotificationService.buildReminderId(
                                        bill.title,
                                        bill.dueDate,
                                      );

                                  if (value) {
                                    await NotificationService().scheduleReminder(
                                      id: reminderId,
                                      title: 'Bill due: ${bill.title}',
                                      body:
                                          '${bill.description} — ₹${formatCurrency(bill.amount)}',
                                      scheduledDate: DateTime(
                                        bill.dueDate.year,
                                        bill.dueDate.month,
                                        bill.dueDate.day,
                                        bill.reminderHour,
                                        bill.reminderMinute,
                                      ),
                                    );
                                  } else {
                                    await NotificationService().cancel(
                                      reminderId,
                                    );
                                  }

                                  await _saveAllBills();

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        value
                                            ? 'Reminder set for ${bill.title}'
                                            : 'Reminder removed',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                onDelete: () async => deleteBill(bill),
                                onEdit: () => openAddBillPage(billToEdit: bill),
                                onCompletionChanged: (value) async {
                                  setState(() {
                                    bill.isCompleted = value;
                                  });
                                  await _saveAllBills();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FloatingActionButton.extended(
            onPressed: () => openAddBillPage(),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 8,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Add Bill',
              style: GoogleFonts.googleSans(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _openSupportEmail,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Support',
                      style: GoogleFonts.googleSans(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '  . ',
                    style: GoogleFonts.googleSans(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://imbhuvanesh.github.io/dev/'),
                    ),
                    child: Text(
                      'bhuvy',
                      style: GoogleFonts.googleSans(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BILL CARD
// ============================================================

class BillCard extends StatefulWidget {
  final Bill bill;
  final String dueDate;
  final ValueChanged<bool> onReminderChanged;
  final ValueChanged<bool> onCompletionChanged;
  final Future<void> Function() onDelete;
  final VoidCallback onEdit;

  const BillCard({
    super.key,
    required this.bill,
    required this.dueDate,
    required this.onReminderChanged,
    required this.onCompletionChanged,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<BillCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController entryController;
  bool showSwipeHint = false;
  int hintGeneration = 0;

  @override
  void initState() {
    super.initState();
    entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    entryController.dispose();
    super.dispose();
  }

  void revealSwipeHint() {
    final generation = ++hintGeneration;
    setState(() {
      showSwipeHint = true;
    });

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || generation != hintGeneration) return;
      setState(() {
        showSwipeHint = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final entryAnimation = CurvedAnimation(
      parent: entryController,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: entryAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(entryAnimation),
        child: GestureDetector(
          onLongPress: revealSwipeHint,
          child: Dismissible(
            key: ValueKey(
              '${widget.bill.title}_${widget.bill.dueDate.toIso8601String()}',
            ),

            direction: DismissDirection.endToStart,

            confirmDismiss: (direction) async {
              await widget.onDelete();
              return true;
            },

            background: Container(
              alignment: Alignment.centerRight,

              padding: const EdgeInsets.only(right: 25),

              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),

                borderRadius: BorderRadius.circular(24),
              ),

              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
            ),

            child: GlassContainer(
              borderRadius: 24,

              child: Column(
                children: [
                  // ===================================================
                  // TOP
                  // ===================================================

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // Icon
                      Container(
                        width: 52,
                        height: 52,

                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),

                          borderRadius: BorderRadius.circular(16),
                        ),

                        // ignore: non_const_argument_for_const_parameter
                        child: Icon(
                          // ignore: non_const_argument_for_const_parameter
                          IconData(
                            // ignore: non_const_argument_for_const_parameter
                            widget.bill.iconCodePoint,
                            fontFamily: 'MaterialIcons',
                          ),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              widget.bill.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,

                              style: GoogleFonts.googleSans(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              widget.bill.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,

                              style: GoogleFonts.googleSans(
                                fontSize: 12.5,
                                color: Colors.white54,
                              ),
                            ),

                            if (widget.bill.isCompleted) ...[
                              const SizedBox(height: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Completed',
                                  style: GoogleFonts.googleSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 10),

                      IconButton(
                        tooltip: widget.bill.isCompleted
                            ? 'Mark as incomplete'
                            : 'Mark as completed',
                        onPressed: () => widget.onCompletionChanged(
                          !widget.bill.isCompleted,
                        ),
                        icon: Icon(
                          widget.bill.isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          color: widget.bill.isCompleted
                              ? Colors.greenAccent
                              : Colors.white54,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),

                      // Amount
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${formatCurrency(widget.bill.amount)}',
                            style: GoogleFonts.googleSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'amount',
                            style: GoogleFonts.googleSans(
                              fontSize: 10,
                              color: Colors.white30,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ===================================================
                  // DIVIDER
                  // ===================================================
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),

                  const SizedBox(height: 14),

                  // ===================================================
                  // BOTTOM
                  // ===================================================
                  Row(
                    children: [
                      // Due date
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),

                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),

                          borderRadius: BorderRadius.circular(10),
                        ),

                        child: Row(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 14,
                              color: Colors.white54,
                            ),

                            const SizedBox(width: 7),

                            Text(
                              'Due ${widget.dueDate}',
                              style: GoogleFonts.googleSans(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: GoogleFonts.googleSans(fontSize: 11.5),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Reminder
                      GestureDetector(
                        onTap: () {
                          widget.onReminderChanged(
                            !widget.bill.reminderEnabled,
                          );
                        },

                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),

                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),

                          decoration: BoxDecoration(
                            color: widget.bill.reminderEnabled
                                ? Colors.green.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),

                            borderRadius: BorderRadius.circular(12),

                            border: Border.all(
                              color: widget.bill.reminderEnabled
                                  ? Colors.greenAccent.withValues(alpha: 0.55)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),

                          child: Row(
                            mainAxisSize: MainAxisSize.min,

                            children: [
                              Icon(
                                widget.bill.reminderEnabled
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_none_rounded,

                                size: 16,
                                color: widget.bill.reminderEnabled
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),

                              const SizedBox(width: 7),

                              Text(
                                widget.bill.reminderEnabled
                                    ? 'Reminder set'
                                    : 'Remind me',

                                style: GoogleFonts.googleSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: widget.bill.reminderEnabled
                                      ? Colors.greenAccent
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: showSwipeHint
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.swipe_left_rounded,
                                  size: 16,
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Swipe left to delete',
                                  style: GoogleFonts.googleSans(
                                    fontSize: 11,
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.85,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ADD BILL SCREEN
// ============================================================

class AddBillScreen extends StatefulWidget {
  final Bill? initialBill;

  const AddBillScreen({super.key, this.initialBill});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final TextEditingController titleController = TextEditingController();

  final TextEditingController descriptionController = TextEditingController();

  final TextEditingController amountController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay selectedReminderTime = const TimeOfDay(hour: 0, minute: 0);

  int selectedIcon = Icons.receipt_long_rounded.codePoint;
  bool reminderEnabled = false;

  final List<int> icons = [
    Icons.receipt_long_rounded.codePoint,
    Icons.bolt_rounded.codePoint,
    Icons.wifi_rounded.codePoint,
    Icons.phone_android_rounded.codePoint,
    Icons.movie_outlined.codePoint,
    Icons.home_outlined.codePoint,
    Icons.local_gas_station_outlined.codePoint,
    Icons.shopping_bag_outlined.codePoint,
  ];

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    amountController.dispose();

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final bill = widget.initialBill;
    if (bill == null) {
      return;
    }

    titleController.text = bill.title;
    descriptionController.text = bill.description;
    amountController.text = cleanAmountInput(bill.amount.toString());
    selectedDate = bill.dueDate;
    selectedIcon = bill.iconCodePoint;
    reminderEnabled = bill.reminderEnabled;
    selectedReminderTime = TimeOfDay(
      hour: bill.reminderHour,
      minute: bill.reminderMinute,
    );
  }

  // ==========================================================
  // DATE PICKER
  // ==========================================================

  Future<void> pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,

      initialDate: selectedDate ?? DateTime.now(),

      firstDate: widget.initialBill == null ? DateTime.now() : DateTime(2000),

      lastDate: DateTime(2100),

      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF151820),
            ),
          ),

          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedReminderTime,
    );

    if (picked != null) {
      setState(() {
        selectedReminderTime = picked;
      });
    }
  }

  // ==========================================================
  // SAVE BILL
  // ==========================================================

  void saveBill() {
    final title = titleController.text.trim();

    final description = descriptionController.text.trim();

    final amount = parseAmountInput(amountController.text);

    if (title.isEmpty || amount == null || selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the bill name, amount and due date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final bill = Bill(
      title: title,
      description: description.isEmpty ? 'Bill payment' : description,
      amount: amount,
      dueDate: selectedDate!,
      iconCodePoint: selectedIcon,
      reminderEnabled: reminderEnabled,
      isCompleted: widget.initialBill?.isCompleted ?? false,
      reminderHour: selectedReminderTime.hour,
      reminderMinute: selectedReminderTime.minute,
    );

    Navigator.pop(context, bill);
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),

      body: Stack(
        children: [
          const AppBackground(),

          SafeArea(
            child: Column(
              children: [
                // =================================================
                // TOP BAR
                // =================================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 10),

                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,

                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),

                      const SizedBox(width: 14),

                      Text(
                        widget.initialBill == null ? 'Add Bill' : 'Edit Bill',
                        style: GoogleFonts.googleSans(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // =================================================
                // CONTENT
                // =================================================
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          widget.initialBill == null
                              ? 'Create a new bill'
                              : 'Update your bill',
                          style: GoogleFonts.googleSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),

                        const SizedBox(height: 7),

                        Text(
                          'Add the details and keep track of your payment.',
                          style: GoogleFonts.googleSans(
                            fontSize: 14,
                            color: Colors.white54,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // =================================================
                        // BILL NAME
                        // =================================================
                        GlassTextField(
                          controller: titleController,
                          label: 'Bill name',
                          hint: 'e.g. Electricity',
                          icon: Icons.receipt_long_outlined,
                        ),

                        const SizedBox(height: 14),

                        // =================================================
                        // DESCRIPTION
                        // =================================================
                        GlassTextField(
                          controller: descriptionController,
                          label: 'Description',
                          hint: 'e.g. Home electricity bill',
                          icon: Icons.notes_rounded,
                        ),

                        const SizedBox(height: 14),

                        // =================================================
                        // AMOUNT
                        // =================================================
                        GlassTextField(
                          controller: amountController,
                          label: 'Amount',
                          hint: 'e.g. 1,00,000',
                          icon: Icons.currency_rupee_rounded,
                          keyboardType: TextInputType.text,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.]'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // =================================================
                        // DATE
                        // =================================================
                        GestureDetector(
                          onTap: pickDate,

                          child: GlassContainer(
                            borderRadius: 18,

                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,

                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.07),

                                    borderRadius: BorderRadius.circular(14),
                                  ),

                                  child: const Icon(
                                    Icons.calendar_month_outlined,
                                    color: Colors.white70,
                                  ),
                                ),

                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,

                                    children: [
                                      Text(
                                        'Due date',
                                        style: GoogleFonts.googleSans(
                                          fontSize: 12,
                                          color: Colors.white54,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        selectedDate == null
                                            ? 'Select a date'
                                            : formatFullDate(selectedDate!),

                                        style: GoogleFonts.googleSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: selectedDate == null
                                              ? Colors.white38
                                              : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white38,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        GestureDetector(
                          onTap: pickReminderTime,
                          child: GlassContainer(
                            borderRadius: 18,
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.access_time_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Reminder time',
                                        style: GoogleFonts.googleSans(
                                          fontSize: 12,
                                          color: Colors.white54,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        selectedReminderTime.format(context),
                                        style: GoogleFonts.googleSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white38,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // =================================================
                        // ICON
                        // =================================================
                        Text(
                          'Choose an icon',
                          style: GoogleFonts.googleSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 12),

                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: icons.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1,
                              ),
                          itemBuilder: (context, index) {
                            final icon = icons[index];
                            final isSelected = icon == selectedIcon;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedIcon = icon;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.08),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.18,
                                            ),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                                // ignore: non_const_argument_for_const_parameter
                                child: Icon(
                                  // ignore: non_const_argument_for_const_parameter
                                  IconData(icon, fontFamily: 'MaterialIcons'),
                                  color: Colors.white,
                                  size: 23,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 35),

                        // =================================================
                        // SAVE BUTTON
                        // =================================================
                        SizedBox(
                          width: double.infinity,
                          height: 56,

                          child: ElevatedButton(
                            onPressed: saveBill,

                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,

                              foregroundColor: Colors.black,

                              elevation: 0,

                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),

                            child: Text(
                              widget.initialBill == null
                                  ? 'Save Bill'
                                  : 'Update Bill',
                              style: GoogleFonts.googleSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GLASS CONTAINER
// ============================================================

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),

      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),

        child: Container(
          padding: const EdgeInsets.all(17),

          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.065),

            borderRadius: BorderRadius.circular(borderRadius),

            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),

              width: 1,
            ),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),

                blurRadius: 30,

                spreadRadius: -8,
              ),
            ],
          ),

          child: child,
        ),
      ),
    );
  }
}

// ============================================================
// GLASS TEXT FIELD
// ============================================================

class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 18,

      child: TextField(
        controller: controller,

        keyboardType: keyboardType,

        inputFormatters: inputFormatters,

        style: GoogleFonts.googleSans(fontSize: 15, color: Colors.white),

        cursorColor: Colors.white,

        decoration: InputDecoration(
          border: InputBorder.none,

          contentPadding: EdgeInsets.zero,

          labelText: label,

          labelStyle: GoogleFonts.googleSans(
            fontSize: 12,
            color: Colors.white54,
          ),

          hintText: hint,

          hintStyle: GoogleFonts.googleSans(
            fontSize: 14,
            color: Colors.white24,
          ),

          prefixIcon: Icon(icon, color: Colors.white54, size: 21),

          prefixIconConstraints: const BoxConstraints(minWidth: 45),
        ),
      ),
    );
  }
}

// ============================================================
// GLASS ICON BUTTON
// ============================================================

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const GlassIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(15),

        child: Container(
          width: 46,
          height: 46,

          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),

            borderRadius: BorderRadius.circular(15),

            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),

          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black);
  }
}

// ============================================================
// EMPTY STATE
// ============================================================

class EmptyBillsView extends StatelessWidget {
  final VoidCallback onAddBill;

  const EmptyBillsView({super.key, required this.onAddBill});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 80,
              height: 80,

              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),

                borderRadius: BorderRadius.circular(25),
              ),

              child: const Icon(
                Icons.receipt_long_rounded,
                size: 38,
                color: Colors.white54,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'No bills yet',
              style: GoogleFonts.googleSans(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Add your first bill to start\ntracking your payments.',
              textAlign: TextAlign.center,

              style: GoogleFonts.googleSans(
                fontSize: 14,
                height: 1.5,
                color: Colors.white54,
              ),
            ),

            const SizedBox(height: 20),

            TextButton(
              onPressed: onAddBill,

              child: Text(
                'Add your first bill',
                style: GoogleFonts.googleSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DATE FORMAT
// ============================================================

String formatFullDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
