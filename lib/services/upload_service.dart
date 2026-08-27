import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadService {
  static bool _isUploading = false;
  static bool _isFetching = false;
  /// Calls the AWS Lambda to get a presigned URL, then uploads the file to S3.
  /// [apiUrl] The Lambda function endpoint URL
  /// [filePath] The local path of the file to upload
  /// [folderPath] The target folder path in S3 (and DB)
  static Future<void> uploadFile({
    required String apiUrl,
    required String filePath,
    required String folderPath,
    String? customFileName,
  }) async {
    if (_isUploading) {
      throw StateError('An upload is already in progress. Please wait.');
    }
    
    _isUploading = true;
    try {
      File file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      String fileName = customFileName ?? path.basename(filePath);
      String mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      // Check if file is an image, if so compress and convert to webp
      if (mimeType.startsWith('image/')) {
        final tempDir = await getTemporaryDirectory();
        final targetPath = path.join(
          tempDir.path, 
          '${path.basenameWithoutExtension(fileName)}.webp'
        );
        
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          quality: 75,
          format: CompressFormat.webp,
        );

        if (compressedFile != null) {
          file = File(compressedFile.path);
          fileName = customFileName != null 
              ? '${path.basenameWithoutExtension(customFileName)}.webp' 
              : path.basename(compressedFile.path);
          mimeType = 'image/webp';
        }
      }

      // 1. Get presigned URL from AWS Lambda
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fileName': fileName,
          'folderPath': folderPath,
          'contentType': mimeType,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get presigned URL: ${response.body}');
      }

      final responseData = jsonDecode(response.body);
      final presignedUrl = responseData['presignedUrl'];
      
      if (presignedUrl == null) {
        throw Exception('Lambda response did not contain presignedUrl.');
      }

      // 2. Upload file to S3 using the presigned URL
      final fileBytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(presignedUrl),
        headers: {
          'Content-Type': mimeType,
        },
        body: fileBytes,
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload file to S3: ${uploadResponse.statusCode} ${uploadResponse.body}');
      }

      print('Upload successful!');
    } catch (e) {
      print('Upload failed: $e');
      rethrow;
    } finally {
      _isUploading = false;
    }
  }

  /// Fetches the list of uploaded files from the Lambda GET endpoint.
  static Future<List<dynamic>> fetchUploadedFiles(String apiUrl, {bool forceRefresh = false}) async {
    if (_isFetching) {
      throw StateError('A fetch request is already in progress. Please wait.');
    }
    
    _isFetching = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!forceRefresh) {
        final cachedData = prefs.getString('gallery_cache');
        if (cachedData != null) {
          return jsonDecode(cachedData);
        }
      }

      final response = await http.get(Uri.parse(apiUrl));
      
      if (response.statusCode == 200) {
        // Save to cache
        await prefs.setString('gallery_cache', response.body);
        final List<dynamic> data = jsonDecode(response.body);
        return data;
      } else {
        throw Exception('Failed to fetch photos: ${response.statusCode}');
      }
    } finally {
      _isFetching = false;
    }
  }
  static Future<void> deleteFile({
    required String apiUrl,
    required String fileName,
    required String folderPath,
  }) async {
    final response = await http.delete(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': fileName,
        'folderPath': folderPath,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete file: ${response.body}');
    }
  }
}
