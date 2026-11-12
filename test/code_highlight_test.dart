import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/code_highlight.dart';

/// 代码块高亮的分词器。
///
/// 这里守两条底线：分词只换颜色、不改原文（少一个字符，复制出去就是错的代码），
/// 以及语言认得出——认错语言的后果是整段颜色乱掉，比不着色还难看。
void main() {
  String flatten(TextSpan span) {
    final buffer = StringBuffer();
    void visit(InlineSpan node) {
      if (node is! TextSpan) return;
      if (node.text != null) buffer.write(node.text);
      node.children?.forEach(visit);
    }

    visit(span);
    return buffer.toString();
  }

  String textOfColor(TextSpan span, Color color) {
    final buffer = StringBuffer();
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan && child.style?.color == color && child.text != null) {
        buffer.write(child.text);
      }
    }
    return buffer.toString();
  }

  group('识别语言', () {
    final samples = <String, CodeLanguage>{
      'smali': CodeLanguage.smali,
      'shell': CodeLanguage.shell,
      'java': CodeLanguage.java,
      'kotlin': CodeLanguage.kotlin,
      'python': CodeLanguage.python,
      'json': CodeLanguage.json,
      'xml': CodeLanguage.xml,
      'php': CodeLanguage.php,
      'c': CodeLanguage.c,
      'sql': CodeLanguage.sql,
    };

    const codes = <String, String>{
      'smali': '.method public onCreate()V\n    .locals 2\n    const-string v0, "x"\n    return-void\n.end method',
      'shell': r'$ adb shell pm list packages',
      'java': 'public class Main {\n  void run() {}\n}',
      'kotlin': 'fun main() {\n  val a = 1\n}',
      'python': 'def main():\n    pass',
      'json': '{"name": "mt", "count": 2}',
      'xml': '<manifest package="cc.binmt.mt_forum"></manifest>',
      'php': '<?php echo 1;',
      'c': '#include <stdio.h>\nint main() { return 0; }',
      'sql': 'SELECT id FROM posts WHERE id = 1',
    };

    for (final entry in samples.entries) {
      test('${entry.key} 片段按内容认得出', () {
        expect(
          CodeHighlight.detect(codes[entry.key]!),
          entry.value,
          reason: '${entry.key} 认错语言，整段颜色都会乱',
        );
      });
    }

    test('带 language- 前缀的 class 优先于内容判断', () {
      // 内容是 Java 的样子，但站点标了 python，按站点的来。
      const code = 'import java.util.List;\n';
      expect(CodeHighlight.detect(code, classes: const <String>['language-python']), CodeLanguage.python);
      expect(CodeHighlight.detect(code, classes: const <String>['brush: java']), CodeLanguage.java);
      expect(CodeHighlight.detect(code, classes: const <String>['hljs', 'language-kotlin']), CodeLanguage.kotlin);
    });

    test('认不出来就是 none，不硬套', () {
      expect(CodeLanguage.none.label, '代码');
      expect(CodeHighlight.detect('随手写的一句话'), CodeLanguage.none);
    });
  });

  group('着色', () {
    test('颜色换来换去，原文一个字都不能少', () {
      const code = 'public class A {\n  // 中文注释\n  String s = "x";\n  int n = 0x1F;\n}';
      final span = CodeHighlight.span(code, CodeLanguage.java);
      expect(flatten(span), code);
    });

    test('关键字、字符串、注释、数字各上各的色', () {
      const code = 'public class A {\n  // hi\n  String s = "x";\n  int n = 42;\n}';
      final span = CodeHighlight.span(code, CodeLanguage.java);
      expect(textOfColor(span, CodeHighlight.keywordColor), contains('public'));
      expect(textOfColor(span, CodeHighlight.stringColor), contains('"x"'));
      expect(textOfColor(span, CodeHighlight.commentColor), contains('// hi'));
      expect(textOfColor(span, CodeHighlight.numberColor), contains('42'));
    });

    test('smali 的 .method 和 invoke-virtual 当关键字', () {
      const code = '.method public foo()V\n    invoke-virtual {v0}, Ljava/lang/String;->length()I\n.end method';
      final span = CodeHighlight.span(code, CodeLanguage.smali);
      final keywords = textOfColor(span, CodeHighlight.keywordColor);
      expect(keywords, contains('.method'));
      expect(keywords, contains('invoke-virtual'));
    });

    test('shell 里词中间的 # 不算注释', () {
      final span = CodeHighlight.span('echo a#b', CodeLanguage.shell);
      expect(textOfColor(span, CodeHighlight.commentColor), isEmpty);
      expect(flatten(span), 'echo a#b');
    });

    test('没闭合的引号只吃到行尾，不吞掉后面的代码', () {
      const code = 'String s = "oops\nint x = 1;';
      final span = CodeHighlight.span(code, CodeLanguage.java);
      expect(textOfColor(span, CodeHighlight.stringColor), '"oops');
      expect(textOfColor(span, CodeHighlight.keywordColor), contains('int'));
      expect(flatten(span), code);
    });

    test('未知语言原样输出，只是不着色', () {
      const code = '这是一段随便写的文字 with 空格';
      final span = CodeHighlight.span(code, CodeLanguage.none);
      expect(flatten(span), code);
    });
  });

  group('行号', () {
    test('从 1 开始，逐行递增', () {
      expect(CodeHighlight.lineNumbers(1), '1');
      expect(CodeHighlight.lineNumbers(3), '1\n2\n3');
    });

    test('零行给空串', () {
      expect(CodeHighlight.lineNumbers(0), '');
      expect(CodeHighlight.lineNumbers(-1), '');
    });
  });
}
