import 'dart:io';

/// Уровень логирования.
enum LogLevel {
  /// Минимальный вывод (только ошибки и критичные сообщения).
  quiet,

  /// Обычный вывод (ошибки, предупреждения, основная информация).
  normal,

  /// Подробный вывод (все сообщения, включая отладочную информацию).
  verbose,
}

/// Логгер для генератора.
class Logger {
  static LogLevel _level = LogLevel.normal;
  static final List<String> _warnings = [];
  static final List<String> _errors = [];

  /// Устанавливает уровень логирования.
  static void setLevel(LogLevel level) {
    _level = level;
  }

  /// Получить текущий уровень логирования.
  static LogLevel get level => _level;

  /// Очистить накопленные предупреждения и ошибки.
  static void clear() {
    _warnings.clear();
    _errors.clear();
  }

  /// Получить список предупреждений.
  static List<String> get warnings => List.unmodifiable(_warnings);

  /// Получить список ошибок.
  static List<String> get errors => List.unmodifiable(_errors);

  /// Вывести информационное сообщение (только в verbose режиме).
  static void verbose(String message) {
    if (_level == LogLevel.verbose) {
      stdout.writeln('ℹ️  $message');
    }
  }

  /// Вывести информационное сообщение (в normal и verbose режимах).
  static void info(String message) {
    if (_level != LogLevel.quiet) {
      stdout.writeln(message);
    }
  }

  /// Вывести предупреждение.
  static void warning(String message) {
    _warnings.add(message);
    if (_level != LogLevel.quiet) {
      stderr.writeln('⚠️  Предупреждение: $message');
    }
  }

  /// Вывести ошибку.
  static void error(String message) {
    _errors.add(message);
    stderr.writeln('❌ Ошибка: $message');
  }

  /// Вывести отладочное сообщение (только в verbose режиме).
  static void debug(String message) {
    if (_level == LogLevel.verbose) {
      stdout.writeln('🔍 $message');
    }
  }

  /// Вывести успешное сообщение.
  static void success(String message) {
    if (_level != LogLevel.quiet) {
      stdout.writeln('✅ $message');
    }
  }
}
