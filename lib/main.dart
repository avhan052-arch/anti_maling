import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:sensors_plus/sensors_plus.dart'; 
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart'; 
// Fitur Intruder Selfie
import 'package:camera/camera.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'intruder_list_screen.dart';
// Variabel global untuk kamera
late List<CameraDescription> cameras;

void main() async {
  // Pastikan binding inisialisasi agar package kamera bisa diakses
  WidgetsFlutterBinding.ensureInitialized(); 
  
  try {
    // Ambil daftar kamera yang tersedia
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error mengakses kamera: $e');
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
  // --- VARIABEL STATUS APLIKASI ---
  bool isActive = false; 
  bool isAlarmTriggered = false; 
  bool isTestMode = false; 
  
  // --- VARIABEL SENSOR & AUDIO ---
  List<double>? _initialPosition; 
  StreamSubscription<UserAccelerometerEvent>? _streamSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _loopTimer; 
  bool _isRedScreen = false;
  double _userPreviousVolume = 0.5; // Untuk menyimpan volume asli user

  // --- VARIABEL PIN & CONTROLLER ---
  final TextEditingController _pinController = TextEditingController();
  final String correctPin = "1234"; 

  // --- VARIABEL KAMERA (Intruder Selfie) ---
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  

  @override
  void initState() {
    super.initState();
    FlutterVolumeController.updateShowSystemUI(false);
    _initializeCamera();
  }

  // --- FUNGSI KAMERA (INTRUDER SELFIE) ---
  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      print("Tidak ada kamera ditemukan.");
      return;
    }
    
    try {
      // Menggunakan kamera index 1 (biasanya kamera depan)
      _cameraController = CameraController(
        cameras[1], 
        ResolutionPreset.low, // Resolusi rendah untuk kecepatan
        enableAudio: false,
      );

      await _cameraController.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      setState(() {
        _isCameraInitialized = false;
      });
      print("Gagal Inisialisasi Kamera: $e");
    }
  }

  Future<void> _captureIntruder() async {
  // [PENTING] Cek apakah kamera sudah siap dan TIDAK sedang mengambil gambar
  if (!_isCameraInitialized || _cameraController.value.isTakingPicture) {
    print("Kamera sedang sibuk atau belum siap. Lewati capture.");
    return;
  }
  
  setState(() {
    _isCapturing = true; // Set flag: Sedang mengambil foto
  });

  try {
    final directory = await getTemporaryDirectory();
    final fileName = 'Intruder_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '${directory.path}/$fileName';
    
    final XFile image = await _cameraController.takePicture();
    
    await image.saveTo(path);

    print('FOTO BUKTI TERSIMPAN KARENA PIN SALAH DI: $path');
    
  } catch (e) {
    print("Error saat mengambil foto: $e");
  } finally {
    setState(() {
      _isCapturing = false; // Reset flag
    });
  }
}


  // --- FUNGSI ALARM & SENSOR ---

  void _activateProtection() async {
    // Cek izin kamera dan inisialisasi status
    if (!_isCameraInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera belum siap/gagal diakses. Alarm aktif tanpa foto.')),
        );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mode Jaga Diaktifkan. Letakkan HP dalam 5 detik...')),
    );

    await Future.delayed(const Duration(seconds: 5));

    setState(() {
      isActive = true;
      _initialPosition = null; 
    });

    // Mulai mendengarkan sensor
    _streamSubscription = userAccelerometerEventStream().listen((event) {
      if (!isActive || isAlarmTriggered) return;

      if (_initialPosition == null) {
        _initialPosition = [event.x, event.y, event.z];
        return;
      }

      // Hitung pergerakan (Sensitivitas: 2.0)
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

    // [FITUR VOLUME LOCK]
    _userPreviousVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    double targetVolume = isTestMode ? 0.3 : 1.0; 
    
    await FlutterVolumeController.setVolume(targetVolume);

    // Mainkan suara sirine
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sirine.mp3'));

    // Loop: Getar, Kedip Layar, dan PAKSA VOLUME
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
      // BAGIAN PIN BENAR (kode tetap sama)
      _streamSubscription?.cancel();
      _loopTimer?.cancel();
      _audioPlayer.stop();
      // ... (reset state lainnya) ...
      
      await FlutterVolumeController.setVolume(_userPreviousVolume);

      setState(() {
        isActive = false;
        isAlarmTriggered = false;
        _pinController.clear();
        _isRedScreen = false;
        // Hapus: _isPhotoTaken = false; (karena flag ini sudah tidak dipakai)
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm Dimatikan. Aman!')),
      );
    } else {
      // BAGIAN PIN SALAH [IMPLEMENTASI BARU]
      
      // 1. Ambil Foto Penyusup
      if (_isCameraInitialized) {
        await Future.delayed(const Duration(milliseconds: 200));
        _captureIntruder();
      }
      
      // 2. Beri Notifikasi PIN Salah
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('PIN SALAH! Foto Penyusup Diambil!')),
      );
      
      // 3. (Opsional) Beri Getaran Panjang agar penyusup kaget
      HapticFeedback.heavyImpact();
    }
}

  // --- DISPOSE: Bersihkan semua controller saat aplikasi ditutup ---
  @override
  void dispose() {
    _streamSubscription?.cancel();
    _loopTimer?.cancel();
    _audioPlayer.dispose();
    _pinController.dispose();
    
    if (_isCameraInitialized) {
      _cameraController.dispose();
    }
    
    super.dispose();
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
                const SizedBox(height: 20),

// [BARU] Tombol Lihat Bukti Foto (Hanya muncul saat alarm tidak aktif)
if (!isActive && !isAlarmTriggered)
  TextButton.icon(
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const IntruderListScreen()),
    ).then((_) {
      // [BARU] Kode ini dijalankan saat user menekan tombol back dari IntruderListScreen
      // (Jika ada state yang perlu di-update di layar utama, bisa diletakkan di sini,
      // tapi untuk kasus ini, ini memastikan layar IntruderListScreen yang akan di-refresh)
      // Sebenarnya, logic refresh harusnya di IntruderListScreen, tapi ini untuk jaga-jaga.
    });
  },
    icon: const Icon(Icons.photo_library, color: Colors.grey),
    label: const Text(
      'Lihat Bukti Foto',
      style: TextStyle(color: Colors.grey),
    ),
  ),
                const SizedBox(height: 50),
              
                // Tombol Toggle Mode Uji
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