/// Normalised API error mirroring the backend's error envelope
/// `{ success:false, statusCode, message, code, errors }`.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.errors,
  });

  final int statusCode;
  final String message;
  final String? code;
  final List<dynamic>? errors;

  bool get isUnauthorized => statusCode == 401;
  bool get isSubscriptionRequired => code == 'SUBSCRIPTION_REQUIRED';
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode, $message${code != null ? ', $code' : ''})';
}
