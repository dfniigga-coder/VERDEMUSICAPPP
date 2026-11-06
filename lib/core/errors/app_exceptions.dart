/// Ошибки приложения с человекочитаемым сообщением на русском.
///
/// Любая ошибка, которая доходит до UI, соответствует ровно одному
/// из подтипов — по ним экраны подбирают текст и кнопки.
class AppException implements Exception {
  final String message;

  const AppException(this.message);

  @override
  String toString() => message;
}

/// Нет сети / таймаут / недоступный сервер.
class NetworkException extends AppException {
  const NetworkException([
    super.message =
        'Нет подключения к сети. Проверьте интернет и попробуйте ещё раз.',
  ]);
}

/// Сервис вернул ошибку или неожиданный ответ.
class ApiException extends AppException {
  final int? statusCode;

  const ApiException([
    super.message = 'Сервис недоступен. Попробуйте позже.',
    this.statusCode,
  ]);
}

/// Трек не загрузился (битый источник, отвалилась сеть и т.п.).
class TrackLoadException extends AppException {
  const TrackLoadException([super.message = 'Не удалось загрузить трек.']);
}

/// Повреждены локальные данные (лайки, плейлисты).
class StorageException extends AppException {
  const StorageException([
    super.message = 'Не удалось прочитать локальные данные.',
  ]);
}
