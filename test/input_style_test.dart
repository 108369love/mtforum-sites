import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：全站只有一套输入控件语言。
///
/// 这轮把 Material 的方框输入、下拉表单、分段按钮逐个换成了玻璃版本，但
/// 以后新加页面很容易又写回 `OutlineInputBorder`。这个测试直接扫源码，
/// 出现退回 Material 的写法就失败，比肉眼 review 靠得住。
///
/// 允许的例外：
/// - `glass_controls.dart`：玻璃控件自己实现，内部当然要用 TextField；
/// - `app_theme.dart`：全局兜底的输入装饰，唯一定义方框圆角的地方；
/// - `thread_page.dart` 的回复框和正文编辑器：嵌在玻璃容器里，输入框本身
///   要「无边框」，所以只允许 `InputBorder.none`。
void main() {
  final lib = Directory('lib');

  List<File> dartFiles() => lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('不该再用 Material 的方框输入（OutlineInputBorder）', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      if (file.path.endsWith('glass_controls.dart') || file.path.endsWith('app_theme.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('OutlineInputBorder')) offenders.add(file.path);
    }
    expect(offenders, isEmpty, reason: '这些文件还在用方框输入，换成 GlassField：${offenders.join(', ')}');
  });

  test('不该再用 DropdownButtonFormField（展开是铺满屏的灰菜单）', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      // 控件源码的注释里会提到被替换掉的旧控件，不算违规。
      if (file.path.endsWith('glass_controls.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('DropdownButtonFormField')) offenders.add(file.path);
    }
    expect(offenders, isEmpty, reason: '换成 GlassSelectRow + showGlassOptionSheet：${offenders.join(', ')}');
  });

  test('不该再用 Material 的 SegmentedButton', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      if (file.path.endsWith('glass_controls.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('SegmentedButton')) offenders.add(file.path);
    }
    expect(offenders, isEmpty, reason: '换成 GlassSegmented：${offenders.join(', ')}');
  });

  test('裸 TextField 只允许出现在输入控件内部或玻璃容器里', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final name = file.path.split('/').last;
      if (name == 'glass_controls.dart') continue;
      final source = file.readAsStringSync();
      var count = RegExp(r'\bTextField\(').allMatches(source).length;
      // 允许「嵌在玻璃卡片里、自己不带边框」的两处正文编辑器。
      count -= RegExp(r'border: InputBorder\.none').allMatches(source).length;
      if (count > 0) offenders.add('${file.path}($count)');
    }
    expect(offenders, isEmpty, reason: '换成 GlassField：${offenders.join(', ')}');
  });
}
