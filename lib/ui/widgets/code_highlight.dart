import 'package:flutter/material.dart';

/// 代码块的语言标签。
///
/// 只列论坛里真会出现的几种：MT 论坛是玩机/逆向社区，代码块基本是 shell、
/// Java/Kotlin、smali 这三类，偶尔夹一段 C、Python、JSON。
enum CodeLanguage {
  none('代码'),
  shell('Shell'),
  java('Java'),
  kotlin('Kotlin'),
  smali('Smali'),
  python('Python'),
  javascript('JavaScript'),
  json('JSON'),
  xml('XML'),
  c('C/C++'),
  php('PHP'),
  sql('SQL');

  const CodeLanguage(this.label);

  /// 代码块左上角显示的名字。
  final String label;
}

/// 代码块的语言识别与轻量高亮。
///
/// 没有引 highlight.js 的 Dart 移植版：那要背 190 种语言的语法表和一堆 pub
/// 依赖，对一个论坛客户端来说太重。这里做的是单遍扫描的分词器——注释、字符串、
/// 数字、关键字、函数名，够把代码块从「一坨白字」变成能一眼扫过去的东西，
/// 也不给包体积和启动速度添负担。
class CodeHighlight {
  const CodeHighlight._();

  /// 调色板按 GitHub Dark 取：代码块底色固定是深色，不随主题走。
  static const Color plainColor = Color(0xFFE6EDF3);
  static const Color keywordColor = Color(0xFFFF7B72);
  static const Color stringColor = Color(0xFFA5D6FF);
  static const Color commentColor = Color(0xFF8B949E);
  static const Color numberColor = Color(0xFF79C0FF);
  static const Color functionColor = Color(0xFFD2A8FF);

  /// 代码块统一用的等宽样式。行号和正文必须共用它，否则两列对不齐。
  static const TextStyle codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12.5,
    height: 1.55,
    color: plainColor,
  );

  /// 行号列的颜色，比正文暗一档，不抢读。
  static const Color gutterColor = Color(0xFF4D5866);

  /// 从 `<pre class="...">`、`<code class="language-xxx">` 这类线索里认出语言，
  /// 认不出来就按内容猜（[detect]）。
  static CodeLanguage detect(String code, {Iterable<String> classes = const <String>[]}) {
    for (final raw in classes) {
      final name = raw.toLowerCase();
      final direct = _aliases[name];
      if (direct != null) return direct;
      for (final prefix in _classPrefixes) {
        if (name.startsWith(prefix)) {
          final aliased = _aliases[name.substring(prefix.length).trim()];
          if (aliased != null) return aliased;
        }
      }
    }
    return _guess(code);
  }

  /// 行号列的内容：`1\n2\n3`。整列用一个 Text 排，比逐行 Widget 省得多。
  static String lineNumbers(int count) {
    if (count <= 0) return '';
    final buffer = StringBuffer('1');
    for (var i = 2; i <= count; i++) {
      buffer.write('\n$i');
    }
    return buffer.toString();
  }

  /// 把代码切成带颜色的 [TextSpan]，文本内容一字不改。
  static TextSpan span(String code, CodeLanguage language) {
    final spec = _specFor(language);
    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    var color = plainColor;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString(), style: TextStyle(color: color)));
      buffer.clear();
    }

    void emit(String text, Color next) {
      if (text.isEmpty) return;
      if (next != color) {
        flush();
        color = next;
      }
      buffer.write(text);
    }

    final length = code.length;
    var i = 0;
    while (i < length) {
      final block = spec.blockComment;
      if (block != null && code.startsWith(block.$1, i)) {
        final close = code.indexOf(block.$2, i + block.$1.length);
        final stop = close < 0 ? length : close + block.$2.length;
        emit(code.substring(i, stop), commentColor);
        i = stop;
        continue;
      }

      final lineComment = _lineCommentAt(code, i, spec);
      if (lineComment != null) {
        var stop = code.indexOf('\n', i);
        if (stop < 0) stop = length;
        emit(code.substring(i, stop), commentColor);
        i = stop;
        continue;
      }

      final ch = code[i];
      if (spec.quotes.contains(ch)) {
        final stop = _scanString(code, i, ch);
        emit(code.substring(i, stop), stringColor);
        i = stop;
        continue;
      }

      if (_isDigit(ch) && (i == 0 || !_isIdentPart(code[i - 1], spec.identExtra))) {
        final stop = _scanNumber(code, i);
        emit(code.substring(i, stop), numberColor);
        i = stop;
        continue;
      }

      // XML 的标签名单独上色，不然整套尖括号看起来跟正文没区别。
      if (spec.xmlTags && ch == '<') {
        emit(ch, plainColor);
        i++;
        if (i < length && _isIdentStart(code[i])) {
          final stop = _scanIdent(code, i, spec.identExtra);
          emit(code.substring(i, stop), keywordColor);
          i = stop;
        }
        continue;
      }

      if (_isIdentStart(ch) || spec.identExtra.contains(ch)) {
        // 允许 `//` 之外、但以 . - / 开头的符号（smali 的 .method、invoke-virtual）。
        final stop = _scanIdent(code, i, spec.identExtra);
        if (stop == i) {
          emit(ch, plainColor);
          i++;
          continue;
        }
        final word = code.substring(i, stop);
        var next = plainColor;
        if (spec.isKeyword(word)) {
          next = keywordColor;
        } else if (spec.jsonKeys && _keyAhead(code, stop)) {
          next = stringColor;
        } else if (stop < length && code[stop] == '(') {
          next = functionColor;
        }
        emit(word, next);
        i = stop;
        continue;
      }

      emit(ch, plainColor);
      i++;
    }
    flush();
    return TextSpan(children: spans, style: codeStyle);
  }

  // ------------------------------------------------------------ 扫描细节

  static String? _lineCommentAt(String code, int index, _Spec spec) {
    for (final marker in spec.lineComments) {
      if (!code.startsWith(marker, index)) continue;
      // shell 的 # 只有出现在行首或空白后面才算注释，`a#b` 是普通字符。
      if (marker == '#' && index > 0) {
        final before = code[index - 1];
        if (before != ' ' && before != '\t' && before != '\n') continue;
      }
      return marker;
    }
    return null;
  }

  static int _scanString(String code, int start, String quote) {
    final length = code.length;
    var i = start + 1;
    while (i < length) {
      final ch = code[i];
      if (ch == '\\') {
        i += 2;
        continue;
      }
      if (ch == quote) return i + 1;
      // 不跨行：帖子里的引号常被截断，别让它把后面几十行都吞成字符串。
      if (ch == '\n') return i;
      i++;
    }
    return length;
  }

  static int _scanNumber(String code, int start) {
    final length = code.length;
    var i = start;
    if (code.startsWith('0x', i) || code.startsWith('0X', i) || code.startsWith('0b', i) || code.startsWith('0B', i)) {
      i += 2;
      while (i < length && (_isHex(code[i]) || code[i] == '_')) {
        i++;
      }
      return i;
    }
    while (i < length && (_isDigit(code[i]) || code[i] == '.' || code[i] == '_')) {
      i++;
    }
    if (i < length && (code[i] == 'e' || code[i] == 'E')) {
      var j = i + 1;
      if (j < length && (code[j] == '+' || code[j] == '-')) j++;
      if (j < length && _isDigit(code[j])) {
        i = j;
        while (i < length && _isDigit(code[i])) {
          i++;
        }
      }
    }
    while (i < length && 'LlfFdDuU'.contains(code[i])) {
      i++;
    }
    return i;
  }

  static int _scanIdent(String code, int start, String extra) {
    final length = code.length;
    var i = start;
    while (i < length && _isIdentPart(code[i], extra)) {
      i++;
    }
    return i;
  }

  /// JSON 的 key：标识符后面跟个冒号。
  static bool _keyAhead(String code, int index) {
    var i = index;
    while (i < code.length && (code[i] == ' ' || code[i] == '\t')) {
      i++;
    }
    return i < code.length && code[i] == ':';
  }

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }

  static bool _isHex(String ch) {
    final c = ch.toLowerCase().codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 97 && c <= 102);
  }

  static bool _isIdentStart(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 0x7F;
  }

  static bool _isIdentPart(String ch, String extra) {
    if (_isIdentStart(ch)) return true;
    if (_isDigit(ch)) return true;
    return extra.contains(ch);
  }

  // ------------------------------------------------------------ 猜测语言

  static CodeLanguage _guess(String code) {
    final head = code.trimLeft();
    if (head.isEmpty) return CodeLanguage.none;
    final lower = head.toLowerCase();

    if (lower.startsWith('<?php')) return CodeLanguage.php;
    if (lower.contains('.method') && (lower.contains('.end method') || lower.contains('.locals'))) {
      return CodeLanguage.smali;
    }
    if (head.startsWith('{') || head.startsWith('[')) {
      if (lower.contains('":') || lower.contains('": ')) return CodeLanguage.json;
    }
    if (head.startsWith('<')) return CodeLanguage.xml;
    if (RegExp(r'^\s*[$>]\s', multiLine: true).hasMatch(head)) return CodeLanguage.shell;
    if (RegExp(r'^\s*(sudo|adb|pm|am|su|cd|ls|rm|cp|mv|chmod|chown|mount|unzip|curl|wget)\s', multiLine: true)
        .hasMatch(head)) {
      return CodeLanguage.shell;
    }
    if (RegExp(r'\bfun\s+\w+\s*\(').hasMatch(head) ||
        RegExp(r'\bimport\s+(androidx|kotlin)\.').hasMatch(head)) {
      return CodeLanguage.kotlin;
    }
    if (RegExp(r'\b(public|private|protected)\s+(static\s+)?(class|void|final|int|String|boolean)\b').hasMatch(head) ||
        RegExp(r'\bimport\s+(java|android)\.').hasMatch(head)) {
      return CodeLanguage.java;
    }
    if (RegExp(r'^\s*def\s+\w+\s*\(', multiLine: true).hasMatch(head) ||
        RegExp(r'^\s*(import|from)\s+\w+', multiLine: true).hasMatch(head) && head.contains(':')) {
      return CodeLanguage.python;
    }
    if (RegExp(r'\b(function|const|let|var)\s+\w+').hasMatch(head) && head.contains(';')) {
      return CodeLanguage.javascript;
    }
    if (head.contains('#include') || RegExp(r'\bint\s+main\s*\(').hasMatch(head)) {
      return CodeLanguage.c;
    }
    if (RegExp(r'\b(select|insert|update|delete)\b[\s\S]*\b(from|into|set|where)\b', caseSensitive: false)
        .hasMatch(head)) {
      return CodeLanguage.sql;
    }
    return CodeLanguage.none;
  }

  // ------------------------------------------------------------ 语言表

  static _Spec _specFor(CodeLanguage language) {
    switch (language) {
      case CodeLanguage.shell:
        return _Spec(
          lineComments: const <String>['#'],
          quotes: const <String>{'"', "'", '`'},
          keywords: _shellKeywords,
        );
      case CodeLanguage.java:
        return _Spec(
          lineComments: const <String>['//'],
          blockComment: const ('/*', '*/'),
          keywords: _javaKeywords,
        );
      case CodeLanguage.kotlin:
        return _Spec(
          lineComments: const <String>['//'],
          blockComment: const ('/*', '*/'),
          keywords: _kotlinKeywords,
        );
      case CodeLanguage.smali:
        return _Spec(
          lineComments: const <String>['#'],
          quotes: const <String>{'"'},
          keywords: _smaliKeywords,
          identExtra: '.-/',
        );
      case CodeLanguage.python:
        return _Spec(
          lineComments: const <String>['#'],
          keywords: _pythonKeywords,
        );
      case CodeLanguage.javascript:
        return _Spec(
          lineComments: const <String>['//'],
          blockComment: const ('/*', '*/'),
          keywords: _jsKeywords,
        );
      case CodeLanguage.json:
        return _Spec(
          lineComments: const <String>['//'],
          keywords: const <String>{'true', 'false', 'null'},
          jsonKeys: true,
        );
      case CodeLanguage.xml:
        return _Spec(
          blockComment: const ('<!--', '-->'),
          keywords: const <String>{},
          xmlTags: true,
        );
      case CodeLanguage.c:
        return _Spec(
          lineComments: const <String>['//'],
          blockComment: const ('/*', '*/'),
          keywords: _cKeywords,
        );
      case CodeLanguage.php:
        return _Spec(
          lineComments: const <String>['//', '#'],
          blockComment: const ('/*', '*/'),
          keywords: _phpKeywords,
        );
      case CodeLanguage.sql:
        return _Spec(
          lineComments: const <String>['--'],
          blockComment: const ('/*', '*/'),
          keywords: _sqlKeywords,
          caseInsensitive: true,
        );
      case CodeLanguage.none:
        return const _Spec();
    }
  }

  static const List<String> _classPrefixes = <String>['language-', 'lang-', 'brush:'];

  static const Map<String, CodeLanguage> _aliases = <String, CodeLanguage>{
    'sh': CodeLanguage.shell,
    'bash': CodeLanguage.shell,
    'zsh': CodeLanguage.shell,
    'shell': CodeLanguage.shell,
    'console': CodeLanguage.shell,
    'shell-session': CodeLanguage.shell,
    'java': CodeLanguage.java,
    'kt': CodeLanguage.kotlin,
    'kts': CodeLanguage.kotlin,
    'kotlin': CodeLanguage.kotlin,
    'smali': CodeLanguage.smali,
    'py': CodeLanguage.python,
    'python': CodeLanguage.python,
    'js': CodeLanguage.javascript,
    'ts': CodeLanguage.javascript,
    'javascript': CodeLanguage.javascript,
    'typescript': CodeLanguage.javascript,
    'json': CodeLanguage.json,
    'xml': CodeLanguage.xml,
    'html': CodeLanguage.xml,
    'c': CodeLanguage.c,
    'h': CodeLanguage.c,
    'cpp': CodeLanguage.c,
    'c++': CodeLanguage.c,
    'php': CodeLanguage.php,
    'sql': CodeLanguage.sql,
  };
}

/// 一门语言的扫描规则。
class _Spec {
  const _Spec({
    this.lineComments = const <String>[],
    this.blockComment,
    this.quotes = const <String>{'"', "'"},
    this.keywords = const <String>{},
    this.identExtra = '',
    this.caseInsensitive = false,
    this.jsonKeys = false,
    this.xmlTags = false,
  });

  final List<String> lineComments;
  final (String, String)? blockComment;
  final Set<String> quotes;
  final Set<String> keywords;

  /// 标识符里额外允许的字符，smali 的 `.method`、`invoke-virtual/range` 靠它。
  final String identExtra;
  final bool caseInsensitive;
  final bool jsonKeys;
  final bool xmlTags;

  bool isKeyword(String word) =>
      keywords.contains(caseInsensitive ? word.toLowerCase() : word);
}

const Set<String> _shellKeywords = <String>{
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', //
  'in', 'function', 'return', 'local', 'export', 'readonly', 'unset', 'source', 'shift', //
  'echo', 'printf', 'cd', 'pwd', 'ls', 'll', 'rm', 'mv', 'cp', 'mkdir', 'rmdir', 'touch', //
  'chmod', 'chown', 'chgrp', 'ps', 'kill', 'killall', 'grep', 'egrep', 'sed', 'awk', 'find', //
  'xargs', 'cat', 'head', 'tail', 'sort', 'uniq', 'wc', 'cut', 'tr', 'tar', 'zip', 'unzip', //
  'curl', 'wget', 'su', 'sudo', 'mount', 'umount', 'adb', 'pm', 'am', 'sh', 'bash', 'exit', //
  'set', 'test', 'which', 'sleep', 'true', 'false', 'exec', 'eval', 'dirname', 'basename',
};

const Set<String> _javaKeywords = <String>{
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const', //
  'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float', //
  'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native', //
  'new', 'package', 'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp', //
  'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try', 'var', 'void', //
  'volatile', 'while', 'record', 'sealed', 'permits', 'true', 'false', 'null',
};

const Set<String> _kotlinKeywords = <String>{
  'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun', 'if', 'in', //
  'interface', 'is', 'null', 'object', 'package', 'return', 'super', 'this', 'throw', 'true', //
  'try', 'typealias', 'typeof', 'val', 'var', 'when', 'while', 'by', 'catch', 'constructor', //
  'delegate', 'dynamic', 'field', 'file', 'finally', 'get', 'import', 'init', 'param', //
  'property', 'receiver', 'set', 'where', 'actual', 'abstract', 'annotation', 'companion', //
  'const', 'crossinline', 'data', 'enum', 'expect', 'external', 'final', 'infix', 'inline', //
  'inner', 'internal', 'lateinit', 'noinline', 'open', 'operator', 'out', 'override', //
  'private', 'protected', 'public', 'reified', 'sealed', 'suspend', 'tailrec', 'vararg',
};

const Set<String> _smaliKeywords = <String>{
  '.class', '.super', '.source', '.method', '.end', '.field', '.annotation', '.line', '.param', //
  '.locals', '.registers', '.prologue', '.local', '.array-data', '.packed-switch', //
  '.sparse-switch', '.catch', '.catchall', '.implements', '.subannotation', '.enum', //
  '.restart', '.limit', '.end field', '.end annotation',
  'invoke-direct', 'invoke-virtual', 'invoke-static', 'invoke-super', 'invoke-interface', //
  'invoke-virtual/range', 'invoke-static/range', 'invoke-direct/range', 'const-string', //
  'const-string/jumbo', 'const/4', 'const/16', 'const/high16', 'const', 'const-wide', //
  'move-result', 'move-result-object', 'move-result-wide', 'move-object', 'move-object/from16', //
  'move', 'move-wide', 'sget-object', 'sput-object', 'sget', 'sput', 'iget', 'iput', //
  'iget-object', 'iput-object', 'new-instance', 'new-array', 'filled-new-array', //
  'if-eq', 'if-ne', 'if-lt', 'if-ge', 'if-gt', 'if-le', 'if-eqz', 'if-nez', 'if-ltz', //
  'if-gez', 'if-gtz', 'if-lez', 'goto', 'goto/16', 'return', 'return-void', 'return-object', //
  'return-wide', 'packed-switch', 'sparse-switch', 'array-length', 'check-cast', //
  'instance-of', 'throw', 'nop', 'aget', 'aput', 'aget-object', 'aput-object', 'div-int', //
  'rem-int', 'mul-int', 'add-int', 'sub-int', 'xor-int', 'and-int', 'or-int', 'shl-int', //
  'shr-int', 'int-to-string', 'long-to-int', 'cmp-long', 'monitor-enter', 'monitor-exit',
};

const Set<String> _pythonKeywords = <String>{
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'import', 'from', 'as', //
  'try', 'except', 'finally', 'with', 'lambda', 'None', 'True', 'False', 'and', 'or', 'not', //
  'in', 'is', 'pass', 'break', 'continue', 'global', 'nonlocal', 'yield', 'raise', 'assert', //
  'del', 'async', 'await', 'self', 'match', 'case',
};

const Set<String> _jsKeywords = <String>{
  'function', 'var', 'let', 'const', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', //
  'default', 'break', 'continue', 'return', 'new', 'class', 'extends', 'super', 'import', //
  'export', 'from', 'as', 'async', 'await', 'try', 'catch', 'finally', 'throw', 'typeof', //
  'instanceof', 'delete', 'in', 'of', 'null', 'undefined', 'true', 'false', 'this', 'void', //
  'yield', 'static', 'get', 'set',
};

const Set<String> _cKeywords = <String>{
  'int', 'char', 'float', 'double', 'void', 'if', 'else', 'for', 'while', 'do', 'switch', //
  'case', 'default', 'break', 'continue', 'return', 'struct', 'union', 'enum', 'typedef', //
  'static', 'const', 'sizeof', 'extern', 'inline', 'volatile', 'unsigned', 'signed', 'long', //
  'short', 'goto', 'register', 'auto', 'include', 'define', 'ifdef', 'ifndef', 'endif', 'pragma',
};

const Set<String> _phpKeywords = <String>{
  'function', 'class', 'interface', 'trait', 'extends', 'implements', 'public', 'private', //
  'protected', 'static', 'const', 'var', 'echo', 'print', 'return', 'if', 'else', 'elseif', //
  'for', 'foreach', 'while', 'do', 'switch', 'case', 'break', 'continue', 'new', 'clone', //
  'try', 'catch', 'finally', 'throw', 'namespace', 'use', 'require', 'include', 'as', //
  'instanceof', 'null', 'true', 'false', 'array', 'list', 'global', 'isset', 'unset', 'empty', //
  'die', 'exit', 'yield', 'fn', 'match', 'readonly', 'enum',
};

const Set<String> _sqlKeywords = <String>{
  'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'join', //
  'left', 'right', 'inner', 'outer', 'on', 'group', 'by', 'order', 'having', 'limit', 'offset', //
  'create', 'table', 'drop', 'alter', 'add', 'column', 'primary', 'key', 'foreign', //
  'references', 'index', 'unique', 'not', 'null', 'default', 'and', 'or', 'in', 'like', //
  'between', 'as', 'distinct', 'count', 'sum', 'avg', 'max', 'min', 'desc', 'asc', 'union', //
  'all', 'exists', 'case', 'when', 'then', 'else', 'end',
};
