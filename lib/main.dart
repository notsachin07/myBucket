import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myBucket/services/upload_service.dart';
import 'package:myBucket/screens/gallery_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S3 Uploader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
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
  final _folderPathController = TextEditingController(text: 'uploads/');
  
  String? _selectedFilePath;
  bool _isUploading = false;
  String _statusMessage = '';
  String _apiUrl = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('api_url') ?? '';
    });
    
    if (_apiUrl.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSettingsDialog();
      });
    }
  }

  Future<void> _saveSettings(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', url);
    setState(() {
      _apiUrl = url;
    });
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: _apiUrl);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('API Configuration'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Lambda API URL',
            hintText: 'https://xxxxx.execute-api.../prod/upload',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _saveSettings(controller.text.trim());
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFile(type: FileType.image);
    if (result != null && result.path != null) {
      setState(() {
        _selectedFilePath = result.path;
        _statusMessage = '';
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFilePath == null) {
      setState(() => _statusMessage = 'Please select a file first.');
      return;
    }
    
    if (_apiUrl.isEmpty) {
      _showSettingsDialog();
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading...';
    });

    try {
      await UploadService.uploadFile(
        apiUrl: _apiUrl,
        filePath: _selectedFilePath!,
        folderPath: _folderPathController.text.trim(),
      );

      setState(() {
        _statusMessage = 'Upload completed successfully!';
        _selectedFilePath = null;
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
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'View Gallery',
            onPressed: () {
              if (_apiUrl.isEmpty) {
                _showSettingsDialog();
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GalleryScreen(apiUrl: _apiUrl),
                ),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 20),
            TextField(
              controller: _folderPathController,
              decoration: InputDecoration(
                labelText: 'Target Folder',
                prefixIcon: const Icon(Icons.folder_open),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _pickFile,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 250,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _selectedFilePath != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(_selectedFilePath!),
                                fit: BoxFit.cover,
                                key: ValueKey(_selectedFilePath),
                              ),
                              Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: Icon(Icons.edit, color: Colors.white, size: 40),
                                ),
                              )
                            ],
                          )
                        : Column(
                            key: const ValueKey('empty'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload, size: 60, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(height: 16),
                              const Text('Tap to select an image', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isUploading || _selectedFilePath == null ? null : _upload,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isUploading
                  ? const SizedBox(
                      height: 24, width: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('Upload to S3', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 24),
            AnimatedOpacity(
              opacity: _statusMessage.isEmpty ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('failed') ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage.contains('failed') ? Colors.red.shade900 : Colors.green.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
