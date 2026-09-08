/// Validate before persisting configuration AND before attaching credentials.
class EndpointPolicy {
  static String validate(String endpoint) {
    final String value = endpoint.trim();
    if (value.isEmpty) return value;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const FormatException(
        'Use an HTTPS endpoint without credentials, query parameters or a fragment.',
      );
    }
    return value;
  }
}
