class InstalledModel {
  const InstalledModel({
    required this.name,
    required this.repository,
    required this.filename,
    required this.path,
    required this.sizeBytes,
  });

  final String name;
  final String repository;
  final String filename;
  final String path;
  final int sizeBytes;
}
