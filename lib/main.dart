import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bills/services/storage_service.dart';
import 'package:bills/services/notification_service.dart';

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

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080A0F),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),

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
  IconData icon;
  bool reminderEnabled;

  Bill({
    required this.title,
    required this.description,
    required this.amount,
    required this.dueDate,
    required this.icon,
    this.reminderEnabled = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'amount': amount,
      'dueDate': dueDate.toIso8601String(),
      'iconCodePoint': icon.codePoint,
      'reminderEnabled': reminderEnabled,
    };
  }

  static Bill fromMap(Map<String, dynamic> m) {
    return Bill(
      title: m['title'] as String,
      description: m['description'] as String,
      amount: (m['amount'] as num).toDouble(),
      dueDate: DateTime.parse(m['dueDate'] as String),
      icon: IconData(m['iconCodePoint'] as int, fontFamily: 'MaterialIcons'),
      reminderEnabled: m['reminderEnabled'] as bool? ?? false,
    );
  }
}

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Bill> bills = [];

  @override
  void initState() {
    super.initState();

    _loadBills();
  }

  Future<void> _loadBills() async {
    final saved = await StorageService().loadBills();
    if (saved.isEmpty) {
      setState(() {
        bills.addAll([
          Bill(
            title: 'Electricity',
            description: 'Home electricity bill',
            amount: 1450,
            dueDate: DateTime(2026, 8, 23),
            icon: Icons.bolt_rounded,
          ),

          Bill(
            title: 'Internet',
            description: 'Monthly broadband payment',
            amount: 899,
            dueDate: DateTime(2026, 8, 20),
            icon: Icons.wifi_rounded,
          ),

          Bill(
            title: 'Netflix',
            description: 'Monthly subscription',
            amount: 649,
            dueDate: DateTime(2026, 8, 28),
            icon: Icons.movie_outlined,
          ),
        ]);
      });
      await _saveAllBills();
      return;
    }

    setState(() {
      bills.addAll(saved.map(Bill.fromMap));
    });
  }

  Future<void> _saveAllBills() async {
    final maps = bills.map((b) => b.toMap()).toList();
    await StorageService().saveBills(maps);
  }

  // ==========================================================
  // ADD BILL
  // ==========================================================

  void openAddBillPage() async {
    final Bill? newBill = await Navigator.push<Bill>(
      context,
      MaterialPageRoute(builder: (context) => const AddBillScreen()),
    );

    if (newBill != null) {
      setState(() {
        bills.add(newBill);
      });
      await _saveAllBills();
    }
  }

  // ==========================================================
  // DELETE BILL
  // ==========================================================

  void deleteBill(int index) {
    setState(() {
      bills.removeAt(index);
    });
    _saveAllBills();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bill deleted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // FORMAT DATE
  // ==========================================================

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

  // ==========================================================
  // TOTAL AMOUNT
  // ==========================================================

  double get totalAmount {
    double total = 0;

    for (final bill in bills) {
      total += bill.amount;
    }

    return total;
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
          // Background
          const AppBackground(),

          SafeArea(
            child: Column(
              children: [
                // =================================================
                // HEADER
                // =================================================

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
                              style: GoogleFonts.inter(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              'Keep your payments on track',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),

                      GlassIconButton(
                        icon: Icons.notifications_none_rounded,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Notifications will appear here'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // =================================================
                // TOTAL CARD
                // =================================================
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),

                  child: GlassContainer(
                    borderRadius: 24,

                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,

                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.09),

                            borderRadius: BorderRadius.circular(17),
                          ),

                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),

                        const SizedBox(width: 16),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                'Total upcoming',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white54,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text(
                                '₹${totalAmount.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),

                            borderRadius: BorderRadius.circular(12),
                          ),

                          child: Text(
                            '${bills.length} bills',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // =================================================
                // UPCOMING TITLE
                // =================================================
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),

                  child: Row(
                    children: [
                      Text(
                        'Upcoming bills',
                        style: GoogleFonts.inter(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const Spacer(),

                      Text(
                        '${bills.length}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // =================================================
                // BILL LIST
                // =================================================
                Expanded(
                  child: bills.isEmpty
                      ? EmptyBillsView(onAddBill: openAddBillPage)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),

                          physics: const BouncingScrollPhysics(),

                          itemCount: bills.length,

                          itemBuilder: (context, index) {
                            final bill = bills[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),

                              child: BillCard(
                                bill: bill,

                                dueDate: formatDate(bill.dueDate),

                                onReminderChanged: (value) async {
                                  setState(() {
                                    bill.reminderEnabled = value;
                                  });

                                  if (value) {
                                    // schedule at 9:00 AM on due date
                                    final scheduled = DateTime(
                                      bill.dueDate.year,
                                      bill.dueDate.month,
                                      bill.dueDate.day,
                                      9,
                                      0,
                                    );

                                    final id = bill
                                        .dueDate
                                        .millisecondsSinceEpoch
                                        .remainder(1 << 31);

                                    await NotificationService().scheduleReminder(
                                      id: id,
                                      title: 'Bill due: ${bill.title}',
                                      body:
                                          '${bill.description} — ₹${bill.amount.toStringAsFixed(0)}',
                                      scheduledDate: scheduled,
                                    );
                                  } else {
                                    final id = bill
                                        .dueDate
                                        .millisecondsSinceEpoch
                                        .remainder(1 << 31);
                                    await NotificationService().cancel(id);
                                  }

                                  await _saveAllBills();

                                  if (!mounted) return;

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

                                onDelete: () {
                                  deleteBill(index);
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

      // =========================================================
      // ADD BUTTON
      // =========================================================
      floatingActionButton: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),

          child: FloatingActionButton.extended(
            onPressed: openAddBillPage,

            backgroundColor: Colors.white,
            foregroundColor: Colors.black,

            elevation: 8,

            icon: const Icon(Icons.add_rounded),

            label: Text(
              'Add Bill',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BILL CARD
// ============================================================

class BillCard extends StatelessWidget {
  final Bill bill;
  final String dueDate;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onDelete;

  const BillCard({
    super.key,
    required this.bill,
    required this.dueDate,
    required this.onReminderChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${bill.title}_${bill.dueDate.toIso8601String()}'),

      direction: DismissDirection.endToStart,

      confirmDismiss: (direction) async {
        onDelete();
        return false;
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

                  child: Icon(bill.icon, color: Colors.white, size: 24),
                ),

                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        bill.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,

                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        bill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,

                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Amount
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,

                  children: [
                    Text(
                      '₹${bill.amount.toStringAsFixed(0)}',

                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'amount',

                      style: GoogleFonts.inter(
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
            Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),

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
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: Colors.white54,
                      ),

                      const SizedBox(width: 7),

                      Text(
                        'Due $dueDate',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Reminder
                GestureDetector(
                  onTap: () {
                    onReminderChanged(!bill.reminderEnabled);
                  },

                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),

                    decoration: BoxDecoration(
                      color: bill.reminderEnabled
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.06),

                      borderRadius: BorderRadius.circular(12),

                      border: Border.all(
                        color: bill.reminderEnabled
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        Icon(
                          bill.reminderEnabled
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,

                          size: 16,
                          color: bill.reminderEnabled
                              ? Colors.white
                              : Colors.white70,
                        ),

                        const SizedBox(width: 7),

                        Text(
                          bill.reminderEnabled ? 'Reminder set' : 'Remind me',

                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ADD BILL SCREEN
// ============================================================

class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final TextEditingController titleController = TextEditingController();

  final TextEditingController descriptionController = TextEditingController();

  final TextEditingController amountController = TextEditingController();

  DateTime? selectedDate;

  IconData selectedIcon = Icons.receipt_long_rounded;

  final List<IconData> icons = [
    Icons.receipt_long_rounded,
    Icons.bolt_rounded,
    Icons.wifi_rounded,
    Icons.phone_android_rounded,
    Icons.movie_outlined,
    Icons.home_outlined,
    Icons.local_gas_station_outlined,
    Icons.shopping_bag_outlined,
  ];

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    amountController.dispose();

    super.dispose();
  }

  // ==========================================================
  // DATE PICKER
  // ==========================================================

  Future<void> pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,

      initialDate: selectedDate ?? DateTime.now(),

      firstDate: DateTime.now(),

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

  // ==========================================================
  // SAVE BILL
  // ==========================================================

  void saveBill() {
    final title = titleController.text.trim();

    final description = descriptionController.text.trim();

    final amount = double.tryParse(amountController.text.trim());

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
      icon: selectedIcon,
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
                        'Add Bill',
                        style: GoogleFonts.inter(
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
                          'Create a new bill',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),

                        const SizedBox(height: 7),

                        Text(
                          'Add the details and keep track of your payment.',
                          style: GoogleFonts.inter(
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
                          hint: 'e.g. 1450',
                          icon: Icons.currency_rupee_rounded,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.white54,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        selectedDate == null
                                            ? 'Select a date'
                                            : formatFullDate(selectedDate!),

                                        style: GoogleFonts.inter(
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

                        const SizedBox(height: 24),

                        // =================================================
                        // ICON
                        // =================================================
                        Text(
                          'Choose an icon',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,

                          children: icons.map((icon) {
                            final isSelected = icon == selectedIcon;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedIcon = icon;
                                });
                              },

                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),

                                width: 52,
                                height: 52,

                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.06),

                                  borderRadius: BorderRadius.circular(15),

                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.30)
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),

                                child: Icon(icon, color: Colors.white),
                              ),
                            );
                          }).toList(),
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
                              'Save Bill',
                              style: GoogleFonts.inter(
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

  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 18,

      child: TextField(
        controller: controller,

        keyboardType: keyboardType,

        style: GoogleFonts.inter(fontSize: 15, color: Colors.white),

        cursorColor: Colors.white,

        decoration: InputDecoration(
          border: InputBorder.none,

          contentPadding: EdgeInsets.zero,

          labelText: label,

          labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white54),

          hintText: hint,

          hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white24),

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
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,

              end: Alignment.bottomRight,

              colors: [Color(0xFF10151E), Color(0xFF080A0F), Color(0xFF0D0D15)],
            ),
          ),
        ),

        // Blue glow
        Positioned(
          top: -100,
          right: -100,

          child: Container(
            width: 300,
            height: 300,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: Colors.blue.withValues(alpha: 0.10),
            ),
          ),
        ),

        // Purple glow
        Positioned(
          bottom: -150,
          left: -100,

          child: Container(
            width: 320,
            height: 320,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: Colors.purple.withValues(alpha: 0.08),
            ),
          ),
        ),
      ],
    );
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
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Add your first bill to start\ntracking your payments.',
              textAlign: TextAlign.center,

              style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(
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
