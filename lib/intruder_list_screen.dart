// lib/intruder_list_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class IntruderListScreen extends StatefulWidget {
  const IntruderListScreen({super.key});

  @override
  State<IntruderListScreen> createState() => _IntruderListScreenState();
}

class _IntruderListScreenState extends State<IntruderListScreen> {
  Future<List<File>>? _intruderPhotosFuture;

  @override
  void initState() {
    super.initState();
    _intruderPhotosFuture = _getSavedIntruderPhotos();
  }

  // [BARU] Metode untuk me-refresh data saat layar kembali fokus
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Memuat ulang data setiap kali widget ini menjadi fokus
    setState(() {
      _intruderPhotosFuture = _getSavedIntruderPhotos();
    });
  }

  // Fungsi utama untuk mengambil daftar file foto dari direktori
  Future<List<File>> _getSavedIntruderPhotos() async {
    // 1. Dapatkan direktori sementara (tempat kita menyimpan foto)
    final directory = await getTemporaryDirectory();
    
    // 2. Daftar semua item dalam direktori
    final files = directory.listSync();
    
    // 3. Filter file-file yang namanya diawali "Intruder_"
    // Kita reverse agar foto terbaru muncul di atas
    final photoFiles = files
        .where((item) => 
            item is File && item.path.contains('Intruder_') && item.path.endsWith('.jpg'))
        .map((item) => item as File)
        .toList();
        // [DEBUGGING] Cetak jumlah file yang ditemukan
    print('DEBUG: Ditemukan total ${photoFiles.length} foto penyusup.');
        
    return photoFiles.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bukti Foto Penyusup'),
        backgroundColor: Colors.grey.shade800,
      ),
      backgroundColor: Colors.grey.shade900,
      body: FutureBuilder<List<File>>(
        future: _intruderPhotosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Terjadi Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada bukti foto penyusup yang tersimpan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            );
          }
          
          final photos = snapshot.data!;
          
          // Tampilkan foto dalam GridView (kolom 2)
          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final file = photos[index];
              
              return InkWell(
                onTap: () {
                    // [OPSIONAL] Fungsi untuk melihat foto dalam ukuran penuh
                    // showDialog(context: context, builder: (_) => Image.file(file));
                },
                child: Hero(
                  tag: file.path, // Hero tag untuk transisi animasi (nilai plus UAS)
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.file(
                      file,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.error, color: Colors.red);
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}