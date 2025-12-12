import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart'; // Untuk Sensor Accelerometer
import 'package:audioplayers/audioplayers.dart'; // Untuk Suara
import 'package:vibration/vibration.dart'; // Untuk Getar

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
  bool isActive = false; // Apakah mode jaga aktif?
  bool isAlarmTriggered = false; // Apakah maling terdeteksi?
  
  // Variabel untuk sensor
  List<double>? _initialPosition; // Posisi awal HP saat diletakkan
  StreamSubscription<UserAccelerometerEvent>? _streamSubscription;
  
  // Variabel Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Kontroller input PIN
  final TextEditingController _pinController = TextEditingController();
  final String correctPin = "1234"; // PIN RAHASIA (Ganti sesuka hati)

  // Timer untuk visual layar kedip-kedip
  Timer? _flashTimer;
  bool _isRedScreen = false;

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _flashTimer?.cancel();
    _audioPlayer.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // --- FUNGSI LOGIKA ---

  // 1. Fungsi Mengaktifkan Mode Jaga
  void _activateProtection() async {
    // Beri jeda 5 detik agar user sempat menaruh HP di meja
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Letakkan HP dalam 5 detik...')),
    );

    await Future.delayed(const Duration(seconds: 5));

    setState(() {
      isActive = true;
      _initialPosition = null; // Reset posisi awal
    });

    // Mulai mendengarkan sensor
    // Kita pakai userAccelerometerEventStream agar gravitasi diabaikan (lebih akurat untuk gerakan)
    _streamSubscription = userAccelerometerEventStream().listen((event) {
      if (!isActive || isAlarmTriggered) return;

      // Simpan posisi awal saat pertama kali aktif
      if (_initialPosition == null) {
        _initialPosition = [event.x, event.y, event.z];
        return;
      }

      // Hitung perbedaan pergerakan (Delta)
      double deltaX = (event.x - _initialPosition![0]).abs();
      double deltaY = (event.y - _initialPosition![1]).abs();
      double deltaZ = (event.z - _initialPosition![2]).abs();

      // SENSITIVITAS: Jika gerak lebih dari 2.0, trigger alarm
      // Semakin kecil angkanya, semakin sensitif.
      if (deltaX > 2.0 || deltaY > 2.0 || deltaZ > 2.0) {
        _triggerAlarm();
      }
    });
  }

  // 2. Fungsi Menyalakan Alarm (Maling Terdeteksi!)
  void _triggerAlarm() async {
    setState(() {
      isAlarmTriggered = true;
    });

    // Mainkan suara sirine (looping)
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sirine.mp3'));

    // Getarkan HP
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 1);
    }

    // Mulai efek layar kedip-kedip (Visual Alarm)
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _isRedScreen = !_isRedScreen;
      });
    });
  }

  // 3. Fungsi Mematikan Alarm dengan PIN
  void _stopAlarm() {
    if (_pinController.text == correctPin) {
      // Matikan semua
      _streamSubscription?.cancel();
      _flashTimer?.cancel();
      _audioPlayer.stop();
      Vibration.cancel();
      
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
      // PIN Salah
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('PIN SALAH!')),
      );
    }
  }

  // --- TAMPILAN UI ---
  @override
  Widget build(BuildContext context) {
    // Tampilan Layar Merah/Putih saat Alarm Bunyi
    Color backgroundColor = isAlarmTriggered
        ? (_isRedScreen ? Colors.red : Colors.white)
        : Colors.grey.shade900;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon Gembok Besar
              Icon(
                isActive ? Icons.lock : Icons.lock_open,
                size: 100,
                color: isAlarmTriggered ? Colors.black : Colors.cyanAccent,
              ),
              const SizedBox(height: 20),
              
              // Status Teks
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
                    ? "Masukkan PIN untuk mematikan!"
                    : "Tekan tombol untuk mengaktifkan sensor.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isAlarmTriggered ? Colors.black : Colors.grey),
              ),
              const SizedBox(height: 50),

              // LOGIKA TOMBOL & INPUT PIN
              if (!isActive && !isAlarmTriggered)
                // Tombol Aktivasi
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
                // Input PIN saat Alarm Bunyi
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
                // Tombol Cancel (Saat timer berjalan atau sudah aktif tapi belum bunyi)
                ElevatedButton(
                  onPressed: () {
                     // Reset manual jika ingin membatalkan sebelum maling datang
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
    );
  }
}