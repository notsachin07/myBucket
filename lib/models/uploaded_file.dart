class UploadedFile {
  final String fileName;
  final String folderPath;
  final String s3Url;
  final String previewUrl;

  UploadedFile({
    required this.fileName,
    required this.folderPath,
    required this.s3Url,
    required this.previewUrl,
  });

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      fileName: json['fileName'] ?? '',
      folderPath: json['folderPath'] ?? '',
      s3Url: json['s3Url'] ?? '',
      previewUrl: json['previewUrl'] ?? '',
    );
  }
}
