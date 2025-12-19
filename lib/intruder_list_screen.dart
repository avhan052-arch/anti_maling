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

  Future<List<File>> _getSavedIntruderPhotos() async {
    // 1. Cek Folder
    final directory = await getApplicationDocumentsDirectory();
    debugPrint("📂 Mencari foto di folder: ${directory.path}"); // LOG 1

    if (!await directory.exists()) {
      debugPrint("❌ Folder tidak ditemukan!");
      return [];
    }

    // 2. Cek Semua File
    final files = directory.listSync();
    debugPrint("📂 Total file di folder ini: ${files.length}"); // LOG 2

    // 3. Filter
    final photoFiles = files
    .where((item) {
      // Kita print setiap file yang ditemukan untuk pengecekan
      if (item is File) {
        String name = item.path.split('/').last;
        debugPrint("📄 Menemukan file: $name"); // LOG 3
        return name.startsWith('Intruder_');
      }
      return false;
    })
    .map((item) => item as File)
    .toList();

    debugPrint("✅ Total foto 'Intruder' valid: ${photoFiles.length}"); // LOG 4

    // Urutkan (Terbaru di atas)
    photoFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    return photoFiles;
  }

  void _deletePhoto(File file) async {
    try {
      await file.delete();
      setState(() {
        _intruderPhotosFuture = _getSavedIntruderPhotos();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto dihapus")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menghapus")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bukti Foto"),
        backgroundColor: Colors.grey.shade900,
      ),
      body: FutureBuilder<List<File>>(
        future: _intruderPhotosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.no_photography, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text("Belum ada bukti foto.", style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 5),
                  // Petunjuk untuk user
                  Text(
                    "(Coba picu alarm & masukkan PIN salah)",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400)
                  ),
                ],
              ),
            );
          }

          final photos = snapshot.data!;

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
              return Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.file(file, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: GestureDetector(
                      onTap: () => _deletePhoto(file),
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.delete, size: 16, color: Colors.red),
                      ),
                    ),
                  )
                ],
              );
            },
          );
        },
      ),
    );
  }
}
