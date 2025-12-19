import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:tp6/models/habit.dart';
import 'package:tp6/services/local_storage_service.dart';
import 'package:tp6/services/notification_service.dart';
import 'package:tp6/services/theme_service.dart';
import 'package:tp6/screens/habit_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final _localStorage = LocalStorageService();
  final _notificationService = NotificationService();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _reminderIntervalController = TextEditingController(text: '24');
  final _targetPerWeekController = TextEditingController(text: '7');
  final _maxPerDayController = TextEditingController(text: '1');
  final _uuid = Uuid();

  TimeOfDay? _reminderTime;
  int _weekStartDay = 1; // Monday

  List<Habit> _habits = [];
  String _selectedCategory = 'All';

  Future<void> _loadHabits() async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final list = await _localStorage.getHabitsForUser(userId);

    // Recalculate streaks for all habits
    for (final habit in list) {
      habit.recalculateStreaks();
    }

    setState(() {
      _habits = list;
    });

    // Schedule notifications
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleNotificationsAsync(list);
      });
    }
  }

  Future<void> _scheduleNotificationsAsync(List<Habit> habits) async {
    for (final h in habits) {
      final reminderTime = h.getNextReminderTime();
      if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
        try {
          await _notificationService.cancelNotification(h.id);
          await _notificationService.scheduleHabitReminder(
            id: h.id,
            title: h.title,
            reminderTime: reminderTime,
          );
        } catch (e) {
          // Silently fail
        }
      }
    }
  }

  void _addOrUpdateHabit({String? id}) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final habitId = id ?? _uuid.v4();
    final title = _titleController.text.trim();
    final category = _categoryController.text.trim().isEmpty
        ? 'General'
        : _categoryController.text.trim();
    final reminderInterval =
        int.tryParse(_reminderIntervalController.text) ?? 24;
    final targetPerWeek = int.tryParse(_targetPerWeekController.text) ?? 7;
    final maxPerDay = int.tryParse(_maxPerDayController.text) ?? 1;

    Habit newHabit;
    if (id != null) {
      final existing = await _localStorage.getHabit(id);
      newHabit = Habit(
        id: habitId,
        userId: userId,
        title: title,
        category: category,
        reminderIntervalHours: reminderInterval,
        reminderTime: _reminderTime,
        targetChecksPerWeek: targetPerWeek,
        maxChecksPerDay: maxPerDay,
        weekStartDay: _weekStartDay,
        createdAt: existing?.createdAt,
        checkHistory: existing?.checkHistory ?? [],
        currentStreak: existing?.currentStreak ?? 0,
        bestStreak: existing?.bestStreak ?? 0,
        archived: existing?.archived ?? false,
        pending: true,
      );
    } else {
      newHabit = Habit(
        id: habitId,
        userId: userId,
        title: title,
        category: category,
        reminderIntervalHours: reminderInterval,
        reminderTime: _reminderTime,
        targetChecksPerWeek: targetPerWeek,
        maxChecksPerDay: maxPerDay,
        weekStartDay: _weekStartDay,
        pending: true,
      );
    }

    await _localStorage.saveHabit(newHabit);

    // Clear form
    _titleController.clear();
    _categoryController.clear();
    _reminderIntervalController.text = '24';
    _targetPerWeekController.text = '7';
    _maxPerDayController.text = '1';
    _reminderTime = null;

    await _loadHabits();

    // Schedule notification
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final reminderTime = newHabit.getNextReminderTime();
        if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
          _notificationService.scheduleHabitReminder(
            id: newHabit.id,
            title: newHabit.title,
            reminderTime: reminderTime,
          );
        }
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(id != null ? 'Habit updated' : 'Habit created'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _deleteHabit(String id) async {
    await _localStorage.deleteHabit(id);

    setState(() {
      _habits.removeWhere((h) => h.id == id);
    });

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationService.cancelNotification(id);
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Habit deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _checkHabit(Habit habit) async {
    // Check if can check today
    if (!habit.canCheckToday()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Already checked ${habit.maxChecksPerDay} time${habit.maxChecksPerDay > 1 ? 's' : ''} today!',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Add check
    habit.addCheck(DateTime.now());
    await _localStorage.saveHabit(habit);

    await _loadHabits();

    // Reschedule notification for next reminder
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final reminderTime = habit.getNextReminderTime();
        if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
          _notificationService.cancelNotification(habit.id);
          _notificationService.scheduleHabitReminder(
            id: habit.id,
            title: habit.title,
            reminderTime: reminderTime,
          );
        }
      });
    }

    if (mounted) {
      final status = habit.getStatus();
      String message = 'Great! Habit checked';

      if (habit.currentStreak > 0) {
        message += ' (🔥 ${habit.currentStreak}-week streak)';
      }

      if (status == HabitStatus.weeklyTargetMet) {
        message = '🎉 Weekly target met! $message';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _showAddHabitDialog({String? id}) {
    final formKey = GlobalKey<FormState>();

    if (id != null) {
      final habit = _habits.firstWhere((h) => h.id == id);
      _titleController.text = habit.title;
      _categoryController.text = habit.category;
      _reminderIntervalController.text = habit.reminderIntervalHours.toString();
      _targetPerWeekController.text = habit.targetChecksPerWeek.toString();
      _maxPerDayController.text = habit.maxChecksPerDay.toString();
      _reminderTime = habit.reminderTime;
      _weekStartDay = habit.weekStartDay;
    } else {
      _reminderTime = null;
      _weekStartDay = 1;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id != null ? 'Edit Habit' : 'Add Habit'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Habit Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter a habit title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _targetPerWeekController,
                  decoration: InputDecoration(
                    labelText: 'Target checks per week',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    helperText: 'How many times per week?',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxPerDayController,
                  decoration: InputDecoration(
                    labelText: 'Max checks per day',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    helperText: 'Prevent over-checking',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reminderIntervalController,
                  decoration: InputDecoration(
                    labelText: 'Reminder interval (hours)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    helperText: 'Remind me every X hours',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (context, setDialogState) => ListTile(
                    title: const Text('Reminder Time (optional)'),
                    subtitle: Text(_reminderTime?.format(context) ?? 'Not set'),
                    trailing: const Icon(Icons.access_time),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _reminderTime ?? TimeOfDay.now(),
                      );
                      if (time != null) {
                        setDialogState(() => _reminderTime = time);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (context, setDialogState) =>
                      DropdownButtonFormField<int>(
                        initialValue: _weekStartDay,
                        decoration: InputDecoration(
                          labelText: 'Week starts on',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Sunday')),
                          DropdownMenuItem(value: 1, child: Text('Monday')),
                          DropdownMenuItem(value: 2, child: Text('Tuesday')),
                          DropdownMenuItem(value: 3, child: Text('Wednesday')),
                          DropdownMenuItem(value: 4, child: Text('Thursday')),
                          DropdownMenuItem(value: 5, child: Text('Friday')),
                          DropdownMenuItem(value: 6, child: Text('Saturday')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => _weekStartDay = value);
                          }
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                _addOrUpdateHabit(id: id);
                Navigator.pop(context);
              }
            },
            child: Text(id != null ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      backgroundColor: themeService.isDarkMode
          ? Colors.grey.shade900
          : Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: Colors.deepPurple,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.deepPurple.shade700,
                      Colors.deepPurple.shade500,
                      Colors.purple.shade400,
                    ],
                  ),
                ),
              ),
              title: const Text(
                'My Habits',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    themeService.isDarkMode
                        ? Icons.light_mode
                        : Icons.dark_mode,
                    size: 20,
                  ),
                ),
                onPressed: () => themeService.toggleTheme(),
                tooltip: 'Toggle theme',
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person, size: 20),
                ),
                onPressed: () => Navigator.pushNamed(context, '/profile'),
                tooltip: 'Profile',
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress Summary Card
                  _buildProgressSummaryCard(),
                  const SizedBox(height: 20),

                  // Category Filter
                  _buildCategoryFilter(),
                  const SizedBox(height: 20),

                  // Habits List
                  _buildHabitsList(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHabitDialog(),
        label: const Text(
          'Add Habit',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
      ),
    );
  }

  Widget _buildProgressSummaryCard() {
    final completedToday = _habits
        .where((h) => h.getChecksToday().isNotEmpty)
        .length;
    final total = _habits.length;
    final progress = total == 0 ? 0.0 : completedToday / total;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Progress',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completedToday / $total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).round()}% Complete',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['All', ..._habits.map((h) => h.category).toSet()].map((
              category,
            ) {
              final isSelected = _selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FilterChip(
                  label: Text(
                    category,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : Colors.deepPurple.shade700,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = category);
                  },
                  backgroundColor: Colors.deepPurple.shade50,
                  selectedColor: Colors.deepPurple,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.deepPurple
                          : Colors.deepPurple.shade200,
                      width: isSelected ? 0 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHabitsList() {
    final filtered = _selectedCategory == 'All'
        ? _habits
        : _habits.where((h) => h.category == _selectedCategory).toList();

    // Sort habits
    filtered.sort((a, b) {
      final aStatus = a.getStatus();
      final bStatus = b.getStatus();
      final aPriority = aStatus == HabitStatus.available
          ? 0
          : (aStatus == HabitStatus.weeklyTargetMet ? 1 : 2);
      final bPriority = bStatus == HabitStatus.available
          ? 0
          : (bStatus == HabitStatus.weeklyTargetMet ? 1 : 2);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return b.currentStreak.compareTo(a.currentStreak);
    });

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Colors.deepPurple.shade300,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No habits yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your first habit to get started',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Habits',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...filtered.map((habit) => _buildModernHabitCard(habit)),
      ],
    );
  }

  Widget _buildModernHabitCard(Habit habit) {
    final status = habit.getStatus();
    final checksToday = habit.getChecksToday().length;
    final progress = habit.getWeekProgress();

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.circle_outlined;
    Color cardBorderColor = Colors.transparent;

    if (status == HabitStatus.completedToday) {
      statusColor = Colors.blue;
      statusIcon = Icons.check_circle;
      cardBorderColor = Colors.blue.withOpacity(0.3);
    } else if (status == HabitStatus.weeklyTargetMet) {
      statusColor = Colors.green;
      statusIcon = Icons.stars;
      cardBorderColor = Colors.green.withOpacity(0.3);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorderColor, width: 2),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to detail screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HabitDetailScreen(
                habit: habit,
                onUpdate: () {
                  _loadHabits(); // Reload habits when coming back
                },
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Check button
                  GestureDetector(
                    onTap: () => _checkHabit(habit),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                habit.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                habit.category,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepPurple.shade700,
                                ),
                              ),
                            ),
                            if (habit.currentStreak > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '🔥',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${habit.currentStreak}w',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline, size: 20),
                            SizedBox(width: 12),
                            Text('View Details'),
                          ],
                        ),
                        onTap: () {
                          // Small delay to allow menu to close
                          Future.delayed(const Duration(milliseconds: 100), () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HabitDetailScreen(
                                  habit: habit,
                                  onUpdate: _loadHabits,
                                ),
                              ),
                            );
                          });
                        },
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: const [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                        onTap: () => _showAddHabitDialog(id: habit.id),
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: const [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        onTap: () => _deleteHabit(habit.id),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Week Progress',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          progress,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$checksToday/${habit.maxChecksPerDay}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (status == HabitStatus.weeklyTargetMet)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.celebration,
                          color: Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Weekly target achieved!',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
