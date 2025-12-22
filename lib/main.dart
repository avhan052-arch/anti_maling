import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// Import baru untuk GPS
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';

import 'intruder_list_screen.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error mengakses kamera: $e');
  }

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
  // --- KONFIGURASI TELEGRAM ---
  final String telegramBotToken = "8442607801:AAEhAeiAj5N3yw1ddnwtZjRpkGBMZ6Xaloo";
  final String telegramChatId = "7779707348";


//   Untuk Baterai
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  bool _isChargerMode = false;


  // --- STATUS ---
  bool isActive = false;
  bool isAlarmTriggered = false;
  bool isTestMode = false;

  // --- SENSOR & AUDIO ---
  List<double>? _initialPosition;
  StreamSubscription<UserAccelerometerEvent>? _streamSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _loopTimer;
  bool _isRedScreen = false;
  double _userPreviousVolume = 0.5;

  // --- PIN ---
  final TextEditingController _pinController = TextEditingController();
  final String correctPin = "1234";

  // --- KAMERA & AI ---
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    FlutterVolumeController.updateShowSystemUI(false);
    _initializeCamera();

    // AI Setup
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableClassification: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    try {
      _cameraController = CameraController(
        cameras.length > 1 ? cameras[1] : cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Gagal Inisialisasi Kamera: $e");
    }
  }

  // --- LOGIKA UTAMA: FOTO, AI, GPS, TELEGRAM ---
  Future<void> _processIntruder() async {
    if (!_isCameraInitialized || _isCapturing) return;
    if (_cameraController.value.isTakingPicture) return;

    setState(() => _isCapturing = true);

    try {
      // 1. PERBAIKAN PENYIMPANAN: Gunakan ApplicationDocumentsDirectory (Permanen)
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'Intruder_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '${directory.path}/$fileName';

      // Ambil Foto
      XFile image = await _cameraController.takePicture();
      await image.saveTo(path);

      // 2. ANALISA AI (Face Detection)
      final inputImage = InputImage.fromFilePath(path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      bool faceDetected = faces.isNotEmpty;
      String aiStatus = faceDetected
      ? "WAJAH TERDETEKSI! (${faces.length} orang)"
      : "Gerakan terdeteksi (Wajah tidak jelas).";

      // 3. DAPATKAN LOKASI GPS (Fitur Baru)
      String locationLink = "Lokasi tidak ditemukan";
      try {
        Position position = await _determinePosition();
        // Buat link Google Maps
        locationLink = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
      } catch (e) {
        debugPrint("Gagal ambil lokasi: $e");
        locationLink = "Gagal mengambil GPS: $e";
      }

      // 4. KIRIM KE TELEGRAM
      String caption = "🚨 PERINGATAN MALING! 🚨\n\n"
      "👁️ Status AI: $aiStatus\n"
      "📍 Lokasi: $locationLink\n"
      "🕒 Waktu: ${DateTime.now()}";

      await _sendToTelegram(File(path), caption);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: faceDetected ? Colors.redAccent : Colors.orange,
            content: Text("Bukti + Lokasi dikirim ke Telegram!"),
          ),
        );
      }

    } catch (e) {
      debugPrint("Error System: $e");
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // Fungsi Helper untuk GPS
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Layanan lokasi dimatikan.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Izin lokasi ditolak.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Izin lokasi ditolak permanen.');
    }

    // Ambil lokasi saat ini (High Accuracy)
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _sendToTelegram(File photoFile, String caption) async {
    if (telegramBotToken.contains("GANTI") || telegramChatId.contains("GANTI")) return;

    try {
      var uri = Uri.parse("https://api.telegram.org/bot$telegramBotToken/sendPhoto");
      var request = http.MultipartRequest("POST", uri);

      request.fields['chat_id'] = telegramChatId;
      request.fields['caption'] = caption;

      var pic = await http.MultipartFile.fromPath("photo", photoFile.path);
      request.files.add(pic);

      await request.send();
      debugPrint("Data terkirim ke Telegram");
    } catch (e) {
      debugPrint("Error Telegram: $e");
    }
  }

  // --- ALARM & SENSOR ---
  void _activateProtection() async {
    // Minta izin lokasi di awal agar siap saat maling datang
    await Geolocator.requestPermission();

    // Cek apakah HP sedang dicas saat tombol ditekan?
    if (_isChargerMode) {
      final batteryState = await _battery.batteryState;
      if (batteryState != BatteryState.charging && batteryState != BatteryState.full) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal: HP harus sedang dicas untuk mode ini!'))
          );
        }
        return; // Batalkan aktivasi jika tidak dicas
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mode Jaga AKTIF dalam 5 detik...')));
    }

    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      setState(() {
        isActive = true;
        _initialPosition = null;
      });
    }

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
    if (_isChargerMode) {
      _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
        if (!isActive || isAlarmTriggered) return;
        
        // Jika status berubah jadi "Discharging" (Dicabut), bunyikan alarm
        if (state == BatteryState.discharging) {
          debugPrint("Kabel Charger Dicabut! ALARM!");
          _triggerAlarm();
        }
      });
    }

  }

  void _triggerAlarm() async {
    if (!mounted) return;
    setState(() => isAlarmTriggered = true);

    _userPreviousVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    double targetVolume = isTestMode ? 0.3 : 1.0;

    await FlutterVolumeController.setVolume(targetVolume);
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sirine.mp3'));

    _loopTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() => _isRedScreen = !_isRedScreen);
        HapticFeedback.heavyImpact();
        if (!isTestMode) FlutterVolumeController.setVolume(targetVolume);
      }
    });
  }

  void _stopAlarm() async {
    if (_pinController.text == correctPin) {
      _streamSubscription?.cancel();
      _batterySubscription?.cancel();
      _loopTimer?.cancel();
      _audioPlayer.stop();
      await FlutterVolumeController.setVolume(_userPreviousVolume);

      if (mounted) {
        setState(() {
          isActive = false;
          isAlarmTriggered = false;
          _pinController.clear();
          _isRedScreen = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alarm Mati.')));
      }
    } else {
      // PIN SALAH: Trigger Foto & GPS
      if (_isCameraInitialized) _processIntruder();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text('PIN SALAH! Melacak lokasi...'))
        );
      }
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _loopTimer?.cancel();
    _audioPlayer.dispose();
    _pinController.dispose();
    _faceDetector.close();
    if (_isCameraInitialized) _cameraController.dispose();
    super.dispose();
  }

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
                Icon(isActive ? Icons.lock : Icons.lock_open, size: 100, color: isAlarmTriggered ? Colors.black : Colors.cyanAccent),
                const SizedBox(height: 20),
                Text(isAlarmTriggered ? "MALING TERDETEKSI!" : (isActive ? "Mode Jaga: AKTIF" : "Mode Jaga: MATI"),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isAlarmTriggered ? Colors.black : Colors.white)),
                const SizedBox(height: 10),

                // --- TOMBOL LIHAT BUKTI ---
                if (!isActive && !isAlarmTriggered)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const IntruderListScreen()));
                    },
                    icon: const Icon(Icons.photo_library, color: Colors.grey),
                    label: const Text('Lihat Bukti Foto', style: TextStyle(color: Colors.grey)),
                  ),

                  const SizedBox(height: 30),

                  if (!isActive && !isAlarmTriggered)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: SwitchListTile(
                      title: const Text("Mode Anti-Cabut Charger", style: TextStyle(color: Colors.white)),
                      subtitle: const Text("Alarm bunyi jika kabel dilepas", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: _isChargerMode,
                      activeColor: Colors.cyanAccent,
                      onChanged: (bool value) {
                        setState(() {
                          _isChargerMode = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!isActive && !isAlarmTriggered)
                    TextButton(
                      onPressed: () => setState(() => isTestMode = !isTestMode),
                      child: Text(isTestMode ? "Mode: DEV (Suara Kecil)" : "Mode: PROD (Suara Penuh)", style: TextStyle(color: isTestMode ? Colors.yellow : Colors.grey)),
                    ),
                    const SizedBox(height: 20),

                    if (!isActive && !isAlarmTriggered)
                      ElevatedButton(
                        onPressed: _activateProtection,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                        child: const Text("AKTIFKAN ALARM", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      )
                      else if (isAlarmTriggered)
                        Column(
                          children: [
                            TextField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              decoration: InputDecoration(filled: true, fillColor: Colors.white, hintText: "PIN (1234)", border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _stopAlarm,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                              child: const Text("MATIKAN ALARM", style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        )
                        else
                          ElevatedButton(
                            onPressed: () { _streamSubscription?.cancel(); setState(() => isActive = false); },
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
