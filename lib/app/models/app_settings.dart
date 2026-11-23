class AppSettings {
  const AppSettings({
    this.internetEnabled = false,
    this.remoteBaseUrl = 'https://api.openai.com/v1',
    this.remoteModel = '',
    this.remoteApiToken = '',
    this.huggingFaceToken = '',
  });

  final bool internetEnabled;
  final String remoteBaseUrl;
  final String remoteModel;
  final String remoteApiToken;
  final String huggingFaceToken;

  AppSettings copyWith({
    bool? internetEnabled,
    String? remoteBaseUrl,
    String? remoteModel,
    String? remoteApiToken,
    String? huggingFaceToken,
  }) =>
      AppSettings(
        internetEnabled: internetEnabled ?? this.internetEnabled,
        remoteBaseUrl: remoteBaseUrl ?? this.remoteBaseUrl,
        remoteModel: remoteModel ?? this.remoteModel,
        remoteApiToken: remoteApiToken ?? this.remoteApiToken,
        huggingFaceToken: huggingFaceToken ?? this.huggingFaceToken,
      );
}
