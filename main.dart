import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          brightness: Brightness.dark,
        ),
      ),
      home: const JarvisHome(),
    );
  }
}

class JarvisHome extends StatefulWidget {
  const JarvisHome({Key? key}) : super(key: key);

  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> with WidgetsBindingObserver {
  late FlutterTts flutterTts;
  late stt.SpeechToText _speechToText;
  late SharedPreferences _prefs;
  
  int _currentIndex = 0;
  bool _isListening = false;
  String _voiceLanguage = 'en-US';
  List<Alarm> _alarms = [];
  List<Reminder> _reminders = [];
  List<HabitDay> _habitDays = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _prefs = await SharedPreferences.getInstance();
    flutterTts = FlutterTts();
    _speechToText = stt.SpeechToText();
    
    await flutterTts.setLanguage(_voiceLanguage);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    
    _loadData();
    _startJarvisWelcome();
  }

  Future<void> _startJarvisWelcome() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await flutterTts.speak("Good morning Sir. I am JARVIS, your personal assistant.");
  }

  Future<void> _loadData() async {
    final alarmsJson = _prefs.getString('alarms');
    final remindersJson = _prefs.getString('reminders');
    final habitsJson = _prefs.getString('habits');

    if (alarmsJson != null) {
      final List<dynamic> decoded = jsonDecode(alarmsJson);
      _alarms = decoded.map((e) => Alarm.fromJson(e)).toList();
    }

    if (remindersJson != null) {
      final List<dynamic> decoded = jsonDecode(remindersJson);
      _reminders = decoded.map((e) => Reminder.fromJson(e)).toList();
    }

    if (habitsJson != null) {
      final List<dynamic> decoded = jsonDecode(habitsJson);
      _habitDays = decoded.map((e) => HabitDay.fromJson(e)).toList();
    }

    setState(() {});
    _startAlarmCheck();
  }

  Future<void> _saveData() async {
    await _prefs.setString('alarms', jsonEncode(_alarms.map((e) => e.toJson()).toList()));
    await _prefs.setString('reminders', jsonEncode(_reminders.map((e) => e.toJson()).toList()));
    await _prefs.setString('habits', jsonEncode(_habitDays.map((e) => e.toJson()).toList()));
  }

  void _startAlarmCheck() {
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      final now = DateTime.now();

      for (var alarm in _alarms) {
        if (alarm.isActive && !alarm.triggered) {
          final alarmTime = alarm.getNextTriggerTime();
          if (now.isAfter(alarmTime) && now.difference(alarmTime).inSeconds < 60) {
            _triggerAlarm(alarm);
            alarm.triggered = true;
            await _saveData();
          }
        }
      }

      for (var reminder in _reminders) {
        if (reminder.isActive && !reminder.triggered) {
          final reminderTime = reminder.getNextTriggerTime();
          if (now.isAfter(reminderTime) && now.difference(reminderTime).inSeconds < 60) {
            _triggerReminder(reminder);
            reminder.triggered = true;
            await _saveData();
          }
        }
      }
    });
  }

  Future<void> _triggerAlarm(Alarm alarm) async {
    await flutterTts.speak("Alarm Alert for ${alarm.label}");
    _showAlarmDialog(alarm);
  }

  Future<void> _triggerReminder(Reminder reminder) async {
    await flutterTts.speak("Reminder: ${reminder.label}");
    _showReminderDialog(reminder);
  }

  void _showAlarmDialog(Alarm alarm) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text('ALARM', style: TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.bold)),
        content: Text(alarm.label, style: const TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            onPressed: () {
              Navigator.pop(context);
              alarm.triggered = false;
              _saveData();
            },
            child: const Text('Dismiss', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showReminderDialog(Reminder reminder) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text('REMINDER', style: TextStyle(color: Color(0xFFFFD700))),
        content: Text(reminder.label, style: const TextStyle(color: Colors.white)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            onPressed: () {
              Navigator.pop(context);
              reminder.triggered = false;
              _saveData();
            },
            child: const Text('OK', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _startListening() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize(
        onError: (error) {
          flutterTts.speak("Error listening. Please try again.");
          setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (result) {
            if (result.finalResult) {
              _processVoiceCommand(result.recognizedWords.toLowerCase());
              setState(() => _isListening = false);
            }
          },
          localeId: _voiceLanguage,
        );
      }
    } else {
      _speechToText.stop();
      setState(() => _isListening = false);
    }
  }

  void _processVoiceCommand(String command) async {
    if (command.contains('set alarm') || command.contains('alarm')) {
      await flutterTts.speak("What time should I set the alarm for?");
      setState(() => _currentIndex = 0);
    } else if (command.contains('reminder') || command.contains('remind')) {
      await flutterTts.speak("What reminder should I set?");
      setState(() => _currentIndex = 1);
    } else if (command.contains('habit') || command.contains('tracker')) {
      await flutterTts.speak("Opening habit tracker");
      setState(() => _currentIndex = 2);
    } else if (command.contains('water')) {
      final reminder = Reminder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        label: 'Water Time',
        time: DateTime.now().add(const Duration(hours: 1)),
        isActive: true,
        type: 'water',
      );
      _reminders.add(reminder);
      await _saveData();
      await flutterTts.speak("Water reminder set for one hour from now");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFD700), width: 2),
              ),
              child: const Center(
                child: Text('J', style: TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('JARVIS', style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold)),
                Text('AI Assistant', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButton<String>(
              value: _voiceLanguage,
              dropdownColor: const Color(0xFF2a2a2a),
              items: const [
                DropdownMenuItem(value: 'en-US', child: Text('English')),
                DropdownMenuItem(value: 'hi-IN', child: Text('हिंदी')),
              ],
              onChanged: (value) async {
                setState(() => _voiceLanguage = value ?? 'en-US');
                await flutterTts.setLanguage(_voiceLanguage);
              },
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          AlarmScreen(alarms: _alarms, onSave: _saveData, flutterTts: flutterTts),
          ReminderScreen(reminders: _reminders, onSave: _saveData, flutterTts: flutterTts),
          HabitTrackerScreen(habitDays: _habitDays, onSave: _saveData, flutterTts: flutterTts),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFD700),
        onPressed: _startListening,
        child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.black, size: 28),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1a1a1a),
        selectedItemColor: const Color(0xFFFFD700),
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Alarm'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Reminder'),
          BottomNavigationBarItem(icon: Icon(Icons.track_changes), label: 'Habit'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    flutterTts.stop();
    _speechToText.cancel();
    super.dispose();
  }
}

class AlarmScreen extends StatefulWidget {
  final List<Alarm> alarms;
  final Function() onSave;
  final FlutterTts flutterTts;

  const AlarmScreen({Key? key, required this.alarms, required this.onSave, required this.flutterTts}) : super(key: key);

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  late TextEditingController _labelController;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _addAlarm() {
    if (_labelController.text.isEmpty || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    final now = DateTime.now();
    final alarmDateTime = DateTime(now.year, now.month, now.day, _selectedTime!.hour, _selectedTime!.minute);

    final alarm = Alarm(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text,
      time: alarmDateTime.isBefore(now) ? alarmDateTime.add(const Duration(days: 1)) : alarmDateTime,
      isActive: true,
    );

    widget.alarms.add(alarm);
    widget.onSave();
    widget.flutterTts.speak('Alarm set for ${_selectedTime!.format(context)}');

    _labelController.clear();
    setState(() => _selectedTime = null);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Alarm set: ${alarm.label}')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF2a2a2a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _labelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Alarm Label',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFFFD700))),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _selectTime,
                  child: Text(_selectedTime == null ? 'Select Time' : 'Time: ${_selectedTime!.format(context)}', style: const TextStyle(color: Colors.black)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _addAlarm,
                  child: const Text('Set Alarm', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...widget.alarms.map((alarm) => Card(
          color: const Color(0xFF2a2a2a),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(alarm.label, style: const TextStyle(color: Colors.white)),
            subtitle: Text(DateFormat('hh:mm a').format(alarm.time), style: const TextStyle(color: Colors.grey)),
            trailing: Switch(
              value: alarm.isActive,
              activeColor: const Color(0xFFFFD700),
              onChanged: (value) {
                alarm.isActive = value;
                widget.onSave();
              },
            ),
          ),
        )),
      ],
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }
}

class ReminderScreen extends StatefulWidget {
  final List<Reminder> reminders;
  final Function() onSave;
  final FlutterTts flutterTts;

  const ReminderScreen({Key? key, required this.reminders, required this.onSave, required this.flutterTts}) : super(key: key);

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  late TextEditingController _labelController;
  TimeOfDay? _selectedTime;
  String _reminderType = 'general';

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _addReminder() {
    if (_labelController.text.isEmpty || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    final now = DateTime.now();
    final reminderDateTime = DateTime(now.year, now.month, now.day, _selectedTime!.hour, _selectedTime!.minute);

    final reminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text,
      time: reminderDateTime.isBefore(now) ? reminderDateTime.add(const Duration(days: 1)) : reminderDateTime,
      isActive: true,
      type: _reminderType,
    );

    widget.reminders.add(reminder);
    widget.onSave();
    _labelController.clear();
    setState(() => _selectedTime = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF2a2a2a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _labelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Reminder',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFFFD700))),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: _reminderType,
                  dropdownColor: const Color(0xFF2a2a2a),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'water', child: Text('Water 💧')),
                    DropdownMenuItem(value: 'medicine', child: Text('Medicine 💊')),
                    DropdownMenuItem(value: 'exercise', child: Text('Exercise 🏃')),
                  ],
                  onChanged: (value) => setState(() => _reminderType = value ?? 'general'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _selectTime,
                  child: Text(_selectedTime == null ? 'Select Time' : 'Time: ${_selectedTime!.format(context)}', style: const TextStyle(color: Colors.black)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _addReminder,
                  child: const Text('Add Reminder', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...widget.reminders.map((reminder) => Card(
          color: const Color(0xFF2a2a2a),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(reminder.label, style: const TextStyle(color: Colors.white)),
            subtitle: Text(DateFormat('hh:mm a').format(reminder.time), style: const TextStyle(color: Colors.grey)),
            trailing: Switch(
              value: reminder.isActive,
              activeColor: const Color(0xFFFFD700),
              onChanged: (value) {
                reminder.isActive = value;
                widget.onSave();
              },
            ),
          ),
        )),
      ],
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }
}

class HabitTrackerScreen extends StatefulWidget {
  final List<HabitDay> habitDays;
  final Function() onSave;
  final FlutterTts flutterTts;

  const HabitTrackerScreen({Key? key, required this.habitDays, required this.onSave, required this.flutterTts}) : super(key: key);

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen> {
  late TextEditingController _habitController;
  late TextEditingController _motivationController;

  @override
  void initState() {
    super.initState();
    _habitController = TextEditingController();
    _motivationController = TextEditingController();
    _ensureTodayExists();
  }

  void _ensureTodayExists() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (widget.habitDays.isEmpty || widget.habitDays.last.date != today) {
      widget.habitDays.add(HabitDay(date: today, habits: [], motivation: ''));
      widget.onSave();
    }
  }

  void _addHabit() {
    if (_habitController.text.isEmpty) return;
    _ensureTodayExists();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayHabit = widget.habitDays.firstWhere((h) => h.date == today);
    todayHabit.habits.add({'name': _habitController.text, 'completed': false});
    widget.onSave();
    _habitController.clear();
    setState(() {});
  }

  void _saveMotivation() {
    if (_motivationController.text.isEmpty) return;
    if (_motivationController.text.split(' ').length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 20 words')));
      return;
    }
    _ensureTodayExists();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayHabit = widget.habitDays.firstWhere((h) => h.date == today);
    todayHabit.motivation = _motivationController.text;
    widget.onSave();
    _motivationController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _ensureTodayExists();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayData = widget.habitDays.firstWhere((h) => h.date == today);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF2a2a2a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _habitController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Add Activity',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFFFD700))),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _addHabit,
                  child: const Text('Add Activity', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...todayData.habits.asMap().entries.map((entry) {
          int index = entry.key;
          Map habit = entry.value;
          return Card(
            color: const Color(0xFF2a2a2a),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Checkbox(
                value: habit['completed'],
                activeColor: const Color(0xFFFFD700),
                onChanged: (value) {
                  todayData.habits[index]['completed'] = value ?? false;
                  widget.onSave();
                  setState(() {});
                },
              ),
              title: Text(habit['name'], style: TextStyle(color: Colors.white, decoration: habit['completed'] ? TextDecoration.lineThrough : null)),
            ),
          );
        }),
        const SizedBox(height: 24),
        Card(
          color: const Color(0xFF2a2a2a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _motivationController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Daily motivation (max 20 words)',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFFFD700))),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), minimumSize: const Size(double.infinity, 50)),
                  onPressed: _saveMotivation,
                  child: const Text('Save Motivation', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _habitController.dispose();
    _motivationController.dispose();
    super.dispose();
  }
}

class Alarm {
  String id;
  String label;
  DateTime time;
  bool isActive;
  bool triggered = false;

  Alarm({required this.id, required this.label, required this.time, required this.isActive});

  DateTime getNextTriggerTime() => time;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'time': time.toIso8601String(), 'isActive': isActive, 'triggered': triggered};

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(id: json['id'], label: json['label'], time: DateTime.parse(json['time']), isActive: json['isActive'])..triggered = json['triggered'] ?? false;
}

class Reminder {
  String id;
  String label;
  DateTime time;
  bool isActive;
  bool triggered = false;
  String type;

  Reminder({required this.id, required this.label, required this.time, required this.isActive, this.type = 'general'});

  DateTime getNextTriggerTime() => time;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'time': time.toIso8601String(), 'isActive': isActive, 'triggered': triggered, 'type': type};

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(id: json['id'], label: json['label'], time: DateTime.parse(json['time']), isActive: json['isActive'], type: json['type'] ?? 'general')..triggered = json['triggered'] ?? false;
}

class HabitDay {
  String date;
  List<Map<String, dynamic>> habits;
  String motivation;

  HabitDay({required this.date, required this.habits, required this.motivation});

  Map<String, dynamic> toJson() => {'date': date, 'habits': habits, 'motivation': motivation};

  factory HabitDay.fromJson(Map<String, dynamic> json) => HabitDay(date: json['date'], habits: List<Map<String, dynamic>>.from(json['habits'] ?? []), motivation: json['motivation'] ?? '');
}
