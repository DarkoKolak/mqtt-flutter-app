enum PayloadFormat {
  text,   // raw string (utf8)
  json,   // validates JSON, sends utf8 JSON
  hex,    // user enters hex -> bytes
  base64, // user enters base64 -> bytes
}

extension PayloadFormatLabel on PayloadFormat {
  String get label {
    switch (this) {
      case PayloadFormat.text:
        return 'Raw (Text)';
      case PayloadFormat.json:
        return 'JSON';
      case PayloadFormat.hex:
        return 'Binary (HEX)';
      case PayloadFormat.base64:
        return 'Binary (Base64)';
    }
  }
}