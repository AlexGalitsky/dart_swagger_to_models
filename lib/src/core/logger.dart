import 'dart:io';

/// Logging level.
enum LogLevel {
  /// Minimal output (only errors and critical messages).
  quiet,

  /// Normal output (errors, warnings, main information).
  normal,

  /// Verbose output (all messages, including debug information).
  verbose,
}

/// Logger for generator.
class Logger {
  static LogLevel _level = LogLevel.normal;
  static final List<String> _warnings = [];
  static final List<String> _errors = [];

  /// Sets logging level.
  static void setLevel(LogLevel level) {
    _level = level;
  }

  /// Get current logging level.
  static LogLevel get level => _level;

  /// Clear accumulated warnings and errors.
  static void clear() {
    _warnings.clear();
    _errors.clear();
  }

  /// Get list of warnings.
  static List<String> get warnings => List.unmodifiable(_warnings);

  /// Get list of errors.
  static List<String> get errors => List.unmodifiable(_errors);

  /// Output informational message (only in verbose mode).
  static void verbose(String message) {
    if (_level == LogLevel.verbose) {
      stdout.writeln('ℹ️  $message');
    }
  }

  /// Output informational message (in normal and verbose modes).
  static void info(String message) {
    if (_level != LogLevel.quiet) {
      stdout.writeln(message);
    }
  }

  /// Output warning.
  static void warning(String message) {
    _warnings.add(message);
    if (_level != LogLevel.quiet) {
      stderr.writeln('⚠️  Warning: $message');
    }
  }

  /// Output error.
  static void error(String message) {
    _errors.add(message);
    stderr.writeln('❌ Error: $message');
  }

  /// Output debug message (only in verbose mode).
  static void debug(String message) {
    if (_level == LogLevel.verbose) {
      stdout.writeln('🔍 $message');
    }
  }

  /// Output success message.
  static void success(String message) {
    if (_level != LogLevel.quiet) {
      stdout.writeln('✅ $message');
    }
  }
}
