import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:sensors_plus/sensors_plus.dart'; 
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart'; 

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AntiMalingApp(),
  ));
}

class AntiMalingApp extends StatefulWidget {
  const AntiMalingApp({super.key});

  @override
  State<AntiMalingApp> createState() => _AntiMalingAppState();
}

class _AntiMalingAppState extends State<AntiMalingApp> {
  // --- VARIABEL UTAMA ---
  bool isActive = false; 
  bool isAlarmTriggered = false; 
  bool isTestMode = true; // [BARU] Mode Pengujian

  // Variabel untuk sensor
  List<double>? _initialPosition; 
  StreamSubscription<UserAccelerometerEvent>? _streamSubscription;
  
  // Variabel Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Kontroller input PIN
  final TextEditingController _pinController = TextEditingController();
  final String correctPin = "1234"; 

  // Timer untuk visual & getar berulang
  Timer? _loopTimer; 
  bool _isRedScreen = false;

  // Variabel untuk menyimpan volume asli user sebelum alarm bunyi
  double _userPreviousVolume = 0.5;

  @override
  void initState() {
    super.initState();
    FlutterVolumeController.updateShowSystemUI(false);
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _loopTimer?.cancel();
    _audioPlayer.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // --- FUNGSI LOGIKA ---

  void _activateProtection() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Letakkan HP dalam 5 detik...')),
    );

    await Future.delayed(const Duration(seconds: 5));

    setState(() {
      isActive = true;
      _initialPosition = null; 
    });

    _streamSubscription = userAccelerometerEventStream().listen((event) {
      if (!isActive || isAlarmTriggered) return;

      if (_initialPosition == null) {
        _initialPosition = [event.x, event.y, event.z];
        return;
      }

      double deltaX = (event.x - _initialPosition![0]).abs();
      double deltaY = (event.y - _initialPosition![1]).abs();
      double deltaZ = (event.z - _initialPosition![2]).abs();

      if (deltaX > 2.0 || deltaY > 2.0 || deltaZ > 2.0) {
        _triggerAlarm();
      }
    });
  }

  void _triggerAlarm() async {
    setState(() {
      isAlarmTriggered = true;
    });

    // [LOGIKA VOLUME]
    _userPreviousVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    double targetVolume = isTestMode ? 0.3 : 1.0; // Volume 30% saat Test Mode, 100% saat Normal
    
    await FlutterVolumeController.setVolume(targetVolume);

    // 2. Mainkan suara sirine
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sirine.mp3'));

    // 3. Loop: Getar, Kedip Layar, dan PAKSA VOLUME (Hanya jika BUKAN Test Mode)
    _loopTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _isRedScreen = !_isRedScreen;
      });
      HapticFeedback.heavyImpact(); 
      
      // Volume Lock hanya aktif jika BUKAN Test Mode
      if (!isTestMode) {
        FlutterVolumeController.setVolume(targetVolume);
      }
    });
  }

  void _stopAlarm() async {
    if (_pinController.text == correctPin) {
      _streamSubscription?.cancel();
      _loopTimer?.cancel();
      _audioPlayer.stop();
      
      await FlutterVolumeController.setVolume(_userPreviousVolume);

      setState(() {
        isActive = false;
        isAlarmTriggered = false;
        _pinController.clear();
        _isRedScreen = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm Dimatikan. Aman!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('PIN SALAH!')),
      );
    }
  }

  // --- TAMPILAN UI ---
  @override
  Widget build(BuildContext context) {
    Color backgroundColor = isAlarmTriggered
        ? (_isRedScreen ? Colors.red : Colors.white)
        : Colors.grey.shade900;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView( 
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? Icons.lock : Icons.lock_open,
                  size: 100,
                  color: isAlarmTriggered ? Colors.black : Colors.cyanAccent,
                ),
                const SizedBox(height: 20),
                
                Text(
                  isAlarmTriggered
                      ? "MALING TERDETEKSI!"
                      : (isActive ? "Mode Jaga: AKTIF" : "Mode Jaga: MATI"),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isAlarmTriggered ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isAlarmTriggered
                      ? (isTestMode ? "Volume (30%) TIDAK TERKUNCI" : "Volume (100%) TERKUNCI!")
                      : "Tekan tombol untuk mengaktifkan sensor.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isAlarmTriggered ? Colors.black : Colors.grey),
                ),
                const SizedBox(height: 50),

                // [BARU] Tombol Toggle Mode Uji
                if (!isActive && !isAlarmTriggered)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        isTestMode = !isTestMode;
                      });
                    },
                    child: Text(
                      isTestMode ? "Mode: PENGEMBANGAN (Suara Kecil)" : "Mode: PRODUKSI (Suara Penuh)",
                      style: TextStyle(
                        color: isTestMode ? Colors.yellow : Colors.grey,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                if (!isActive && !isAlarmTriggered)
                  ElevatedButton(
                    onPressed: _activateProtection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text("AKTIFKAN ALARM", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  )
                else if (isAlarmTriggered)
                  Column(
                    children: [
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: "Masukkan PIN (1234)",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _stopAlarm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        ),
                        child: const Text("MATIKAN ALARM", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  )
                else
                  ElevatedButton(
                    onPressed: () {
                       _streamSubscription?.cancel();
                       setState(() => isActive = false);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("BATALKAN", style: TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}