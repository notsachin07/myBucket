import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:myBucket/services/upload_service.dart';
import 'package:myBucket/screens/gallery_screen.dart'; // Make sure package name matches pubspec.yaml

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S3 Uploader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'AWS S3 Upload App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _apiUrlController = TextEditingController();
  final _folderPathController = TextEditingController(text: 'uploads/');
  
  String? _selectedFilePath;
  bool _isUploading = false;
  String _statusMessage = '';

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFile();
    if (result != null && result.path != null) {
      setState(() {
        _selectedFilePath = result.path;
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFilePath == null) {
      setState(() => _statusMessage = 'Please select a file first.');
      return;
    }
    
    if (_apiUrlController.text.trim().isEmpty) {
      setState(() => _statusMessage = 'Please provide the Lambda API URL.');
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading...';
    });

    try {
      await UploadService.uploadFile(
        apiUrl: _apiUrlController.text.trim(),
        filePath: _selectedFilePath!,
        folderPath: _folderPathController.text.trim(),
      );

      setState(() {
        _statusMessage = 'Upload completed successfully!';
        _selectedFilePath = null; // Reset selection on success
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Upload failed: $e';
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _folderPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'View Gallery',
            onPressed: () {
              if (_apiUrlController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide the Lambda API URL first.')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GalleryScreen(apiUrl: _apiUrlController.text.trim()),
                ),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'Lambda API URL',
                hintText: 'https://xxxxx.execute-api.us-east-1.amazonaws.com/prod/upload',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _folderPathController,
              decoration: const InputDecoration(
                labelText: 'Target Folder Path',
                hintText: 'e.g., images/profile',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_selectedFilePath == null ? 'Select File' : 'Change File'),
            ),
            if (_selectedFilePath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Selected: ${_selectedFilePath!.split('/').last}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isUploading ? null : _upload,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Upload to S3'),
            ),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusMessage.contains('failed') ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }
}
