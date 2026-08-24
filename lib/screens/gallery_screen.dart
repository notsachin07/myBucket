import 'package:flutter/material.dart';
import 'package:myBucket/models/uploaded_file.dart';
import 'package:myBucket/services/upload_service.dart';

class GalleryScreen extends StatefulWidget {
  final String apiUrl;
  
  const GalleryScreen({super.key, required this.apiUrl});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Future<List<UploadedFile>> _futureFiles;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  void _fetchFiles() {
    setState(() {
      _futureFiles = UploadService.fetchUploadedFiles(widget.apiUrl)
          .then((data) => data.map((json) => UploadedFile.fromJson(json)).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Gallery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFiles,
          )
        ],
      ),
      body: FutureBuilder<List<UploadedFile>>(
        future: _futureFiles,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No photos uploaded yet.'));
          }

          final files = snapshot.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.network(file.previewUrl),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(file.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    ),
                  );
                },
                child: GridTile(
                  footer: GridTileBar(
                    backgroundColor: Colors.black54,
                    title: Text(file.fileName, style: const TextStyle(fontSize: 10)),
                  ),
                  child: Image.network(
                    file.previewUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
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
