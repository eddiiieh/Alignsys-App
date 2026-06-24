String humanizeError(String raw) {
  final s = raw.toLowerCase();

  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated with hostname') ||
      s.contains('network is unreachable')) {
    return "You're offline. Check your connection and try again.";
  }
  if (s.contains('401')) {
    return 'Your session has expired. Please log in again.';
  }
  if (s.contains('vault is offline') || s.contains('0x80040061')) {
    return 'The repository is temporarily unavailable. Please try again shortly.';
  }
  if (s.contains('timeout') || s.contains('timed out')) {
    return 'The request took too long. Please try again.';
  }
  if (s.contains('clientexception') || s.contains('handshakeexception')) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (s.contains('404')) {
    return "We couldn't find what you were looking for.";
  }
  if (s.contains('500') || s.contains('502') || s.contains('503')) {
    return 'The server ran into a problem. Please try again shortly.';
  }
  return 'Something went wrong. Please try again.';
}