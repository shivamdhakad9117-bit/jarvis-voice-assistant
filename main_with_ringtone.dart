import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:just_audio/just_audio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  
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
  late AudioPlayer _audioPlayer;
  
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
    _audioPlayer = AudioPlayer();
    
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

  Future<void> _playRingtone(String ringtoneType) async {
    try {
      // Ringtone URLs or local assets
      final ringtones = {
        'jarvis': 'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3', // JARVIS voice sample
        'classic': 'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3', // Classic alarm
        'mafia': 'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3', // Mafia theme
      };

      String? url = ringtones[ringtoneType];
      
      if (url != null) {
        await _audioPlayer.setUrl(url);
        await _audioPlayer.play();
      }
    } catch (e) {
      print("Ringtone error: $e");
    }
  }

  Future<void> _triggerAlarm(Alarm alarm) async {
    await flutterTts.speak("Alarm Alert for ${alarm.label}");
    await _playRingtone(alarm.ringtoneType);
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(alarm.label, style: const TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ringtone:', style: TextStyle(color: Colors.grey)),
                  Text(_getRingtoneName(alarm.ringtoneType), style: const TextStyle(color: Color(0xFFFFD700))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            onPressed: () {
              _audioPlayer.stop();
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

  String _getRingtoneName(String type) {
    switch (type) {
      case 'jarvis':
        return '🤖 JARVIS';
      case 'classic':
        return '🔔 Classic';
      case 'mafia':
        return '🎬 Mafia';
      default:
        return 'Unknown';
    }
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
    await flutterTts.speak("Processing command: $command");

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
    } else {
      await flutterTts.speak("I didn't understand that command. Please try again.");
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
                child: Text(
                  'J',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JARVIS',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'AI Assistant',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
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
        child: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: Colors.black,
          size: 28,
        ),
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
    _audioPlayer.dispose();
    super.dispose();
  }
}

// ALARM SCREEN WITH RINGTONE SELECTION
class AlarmScreen extends StatefulWidget {
  final List<Alarm> alarms;
  final Function() onSave;
  final FlutterTts flutterTts;

  const AlarmScreen({
    Key? key,
    required this.alarms,
    required this.onSave,
    required this.flutterTts,
  }) : super(key: key);

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  late TextEditingController _labelController;
  TimeOfDay? _selectedTime;
  String _selectedRingtone = 'jarvis';

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _addAlarm() {
    if (_labelController.text.isEmpty || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final now = DateTime.now();
    final alarmDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final alarm = Alarm(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text,
      time: alarmDateTime.isBefore(now) ? alarmDateTime.add(const Duration(days: 1)) : alarmDateTime,
      isActive: true,
      ringtoneType: _selectedRingtone,
    );

    widget.alarms.add(alarm);
    widget.onSave();
    widget.flutterTts.speak('Alarm set for ${_selectedTime!.format(context)} with $_selectedRingtone ringtone');

    _labelController.clear();
    setState(() {
      _selectedTime = null;
      _selectedRingtone = 'jarvis';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Alarm "${alarm.label}" set for ${_selectedTime!.format(context)}')),
    );
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
                    hintText: 'Alarm Label (e.g., Wake up)',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD700)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFD700)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Select Ringtone 🔔',
                          style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _selectedRingtone,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2a2a2a),
                        items: const [
                          DropdownMenuItem(value: 'jarvis', child: Text('🤖 JARVIS Voice')),
                          DropdownMenuItem(value: 'classic', child: Text('🔔 Classic Alarm')),
                          DropdownMenuItem(value: 'mafia', child: Text('🎬 Mafia Theme')),
                          DropdownMenuItem(value: 'custom', child: Text('🎵 Custom Ringtone')),
                        ],
                        onChanged: (value) => setState(() => _selectedRingtone = value ?? 'jarvis'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _selectTime,
                  child: Text(
                    _selectedTime == null
                        ? 'Select Time'
                        : 'Time: ${_selectedTime!.format(context)}',
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _addAlarm,
                  child: const Text(
                    'Set Alarm',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Your Alarms',
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...widget.alarms.map((alarm) => AlarmTile(alarm: alarm, onSave: widget.onSave)),
      ],
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }
}

class AlarmTile extends StatelessWidget {
  final Alarm alarm;
  final Function() onSave;

  const AlarmTile({Key? key, required this.alarm, required this.onSave}) : super(key: key);

  String _getRingtoneName(String type) {
    switch (type) {
      case 'jarvis':
        return '🤖 JARVIS';
      case 'classic':
        return '🔔 Classic';
      case 'mafia':
        return '🎬 Mafia';
      case 'custom':
        return '🎵 Custom';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2a2a2a),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(alarm.label, style: const TextStyle(color: Colors.white)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('hh:mm a').format(alarm.time),
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              'Ringtone: ${_getRingtoneName(alarm.ringtoneType)}',
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
            ),
          ],
        ),
        trailing: Switch(
          value: alarm.isActive,
          activeColor: const Color(0xFFFFD700),
          onChanged: (value) {
            alarm.isActive = value;
            onSave();
          },
        ),
      ),
    );
  }
}

// REMINDER SCREEN (Same as before)
class ReminderScreen extends StatefulWidget {
  final List<Reminder> reminders;
  final Function() onSave;
  final FlutterTts flutterTts;

  const ReminderScreen({
    Key? key,
    required this.reminders,
    required this.onSave,
    required this.flutterTts,
  }) : super(key: key);

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
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _addReminder() {
    if (_labelController.text.isEmpty || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final now = DateTime.now();
    final reminderDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final reminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text,
      time: reminderDateTime.isBefore(now) ? reminderDateTime.add(const Duration(days: 1)) : reminderDateTime,
      isActive: true,
      type: _reminderType,
    );

    widget.reminders.add(reminder);
    widget.onSave();
    widget.flutterTts.speak('Reminder set for ${_selectedTime!.format(context)}');

    _labelController.clear();
    setState(() => _selectedTime = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder "${reminder.label}" set')),
    );
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
                    hintText: 'Reminder (e.g., Drink Water)',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD700)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: _reminderType,
                  dropdownColor: const Color(0xFF2a2a2a),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'water', child: Text('Water Time 💧')),
                    DropdownMenuItem(value: 'medicine', child: Text('Medicine 💊')),
                    DropdownMenuItem(value: 'exercise', child: Text('Exercise 🏃')),
                  ],
                  onChanged: (value) => setState(() => _reminderType = value ?? 'general'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _selectTime,
                  child: Text(
                    _selectedTime == null
                        ? 'Select Time'
                        : 'Time: ${_selectedTime!.format(context)}',
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _addReminder,
                  child: const Text(
                    'Add Reminder',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Your Reminders',
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...widget.reminders.map((reminder) => ReminderTile(reminder: reminder, onSave: widget.onSave)),
      ],
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }
}

class ReminderTile extends StatelessWidget {
  final Reminder reminder;
  final Function() onSave;

  const ReminderTile({Key? key, required this.reminder, required this.onSave}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final icons = {
      'water': '💧',
      'medicine': '💊',
      'exercise': '🏃',
      'general': '📌',
    };

    return Card(
      color: const Color(0xFF2a2a2a),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Text(icons[reminder.type] ?? '📌', style: const TextStyle(fontSize: 20)),
        title: Text(reminder.label, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          DateFormat('hh:mm a').format(reminder.time),
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: Switch(
          value: reminder.isActive,
          activeColor: const Color(0xFFFFD700),
          onChanged: (value) {
            reminder.isActive = value;
            onSave();
          },
        ),
      ),
    );
  }
}

// HABIT TRACKER SCREEN (Same as before)
class HabitTrackerScreen extends StatefulWidget {
  final List<HabitDay> habitDays;
  final Function() onSave;
  final FlutterTts flutterTts;

  const HabitTrackerScreen({
    Key? key,
    required this.habitDays,
    required this.onSave,
    required this.flutterTts,
  }) : super(key: key);

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

    todayHabit.habits.add({
      'name': _habitController.text,
      'completed': false,
    });

    widget.onSave();
    widget.flutterTts.speak('Habit added: ${_habitController.text}');
    _habitController.clear();
    setState(() {});
  }

  void _saveMotivation() {
    if (_motivationController.text.isEmpty) return;
    if (_motivationController.text.split(' ').length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 20 words allowed')),
      );
      return;
    }

    _ensureTodayExists();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayHabit = widget.habitDays.firstWhere((h) => h.date == today);
    todayHabit.motivation = _motivationController.text;

    widget.onSave();
    widget.flutterTts.speak('Motivation saved');
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
                    hintText: 'Add Activity (e.g., Morning Jog)',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD700)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _addHabit,
                  child: const Text(
                    'Add Activity',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Today's Activities",
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
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
              title: Text(
                habit['name'],
                style: TextStyle(
                  color: Colors.white,
                  decoration: habit['completed'] ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
        const Text(
          'Daily Motivation (20 words max)',
          style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
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
                    hintText: 'Write your daily motivation or notes...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD700)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _saveMotivation,
                  child: const Text(
                    'Save Motivation',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (todayData.motivation.isNotEmpty) ...[
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFF2a2a2a),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today\'s Motivation',
                    style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    todayData.motivation,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
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

// MODELS
class Alarm {
  String id;
  String label;
  DateTime time;
  bool isActive;
  bool triggered = false;
  List<int> repeatDays = [];
  String ringtoneType = 'jarvis'; // NEW: Ringtone type

  Alarm({
    required this.id,
    required this.label,
    required this.time,
    required this.isActive,
    this.ringtoneType = 'jarvis',
  });

  DateTime getNextTriggerTime() {
    return time;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'time': time.toIso8601String(),
      'isActive': isActive,
      'triggered': triggered,
      'repeatDays': repeatDays,
      'ringtoneType': ringtoneType,
    };
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'],
      label: json['label'],
      time: DateTime.parse(json['time']),
      isActive: json['isActive'],
      ringtoneType: json['ringtoneType'] ?? 'jarvis',
    )
      ..triggered = json['triggered'] ?? false
      ..repeatDays = List<int>.from(json['repeatDays'] ?? []);
  }
}

class Reminder {
  String id;
  String label;
  DateTime time;
  bool isActive;
  bool triggered = false;
  String type;

  Reminder({
    required this.id,
    required this.label,
    required this.time,
    required this.isActive,
    this.type = 'general',
  });

  DateTime getNextTriggerTime() {
    return time;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'time': time.toIso8601String(),
      'isActive': isActive,
      'triggered': triggered,
      'type': type,
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'],
      label: json['label'],
      time: DateTime.parse(json['time']),
      isActive: json['isActive'],
      type: json['type'] ?? 'general',
    )..triggered = json['triggered'] ?? false;
  }
}

class HabitDay {
  String date;
  List<Map<String, dynamic>> habits;
  String motivation;

  HabitDay({
    required this.date,
    required this.habits,
    required this.motivation,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'habits': habits,
      'motivation': motivation,
    };
  }

  factory HabitDay.fromJson(Map<String, dynamic> json) {
    return HabitDay(
      date: json['date'],
      habits: List<Map<String, dynamic>>.from(json['habits'] ?? []),
      motivation: json['motivation'] ?? '',
    );
  }
}
