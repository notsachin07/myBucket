import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Map<String, List<UploadedFile>> _groupFilesByFolder(List<UploadedFile> files) {
    final Map<String, List<UploadedFile>> grouped = {};
    for (var file in files) {
      final folder = file.folderPath.isEmpty ? 'Root' : file.folderPath;
      if (!grouped.containsKey(folder)) {
        grouped[folder] = [];
      }
      grouped[folder]!.add(file);
    }
    return grouped;
  }

  void _showImageDetails(BuildContext context, UploadedFile file) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  InteractiveViewer(
                    child: Image.network(
                      file.previewUrl,
                      fit: BoxFit.contain,
                      height: MediaQuery.of(context).size.height * 0.5,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(
                        height: 200,
                        child: Center(child: Icon(Icons.broken_image, size: 50)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                        onPressed: () => _confirmDelete(context, file),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('File Details', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    _buildMetaRow('Name:', file.fileName),
                    _buildMetaRow('Folder:', file.folderPath),
                    _buildMetaRow('Date:', _formatDate(file.uploadedAt)),
                    _buildMetaRow('Type:', file.s3Url.split('.').last.toUpperCase()),
                    _buildUrlRow(context, 'URL:', file.s3Url),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _confirmDelete(BuildContext context, UploadedFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image from the server? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.of(context).pop(); // Close image details dialog
      if (!mounted) return;
      
      // Show loading indicator
      showDialog(
        context: this.context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await UploadService.deleteFile(
          apiUrl: widget.apiUrl,
          fileName: file.fileName,
          folderPath: file.folderPath,
        );
        if (!mounted) return;
        Navigator.of(this.context).pop(); // Dismiss loading
        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Image deleted successfully')));
        _fetchFiles(); // Refresh gallery
      } catch (e) {
        if (!mounted) return;
        Navigator.of(this.context).pop(); // Dismiss loading
        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildUrlRow(BuildContext context, String label, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          Expanded(
            child: Text(url, 
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            padding: const EdgeInsets.only(left: 8.0),
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard!'), duration: Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
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
            return Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No photos uploaded yet.'));
          }

          final groupedFiles = _groupFilesByFolder(snapshot.data!);
          final folders = groupedFiles.keys.toList()..sort();

          return ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              final filesInFolder = groupedFiles[folder]!;
              
              return ExpansionTile(
                initiallyExpanded: index == 0,
                leading: const Icon(Icons.folder, color: Colors.orange),
                title: Text(folder, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${filesInFolder.length} files'),
                children: [
                  GridView.builder(
                    padding: const EdgeInsets.all(12),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: filesInFolder.length,
                    itemBuilder: (context, fileIndex) {
                      final file = filesInFolder[fileIndex];
                      return Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showImageDetails(context, file),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                file.previewUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                },
                              ),
                              Positioned(
                                bottom: 0, left: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  color: Colors.black.withOpacity(0.6),
                                  child: Text(
                                    file.fileName,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
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
