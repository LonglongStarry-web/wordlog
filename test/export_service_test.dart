import 'package:flutter_test/flutter_test.dart';

import 'package:wordlog/models/note.dart';
import 'package:wordlog/models/term.dart';
import 'package:wordlog/services/export_service.dart';

void main() {
  Term t(String name, DateTime at, {String? ctx, bool explained = true}) =>
      Term(
        name: name,
        context: ctx,
        createdAt: at,
        status: explained ? 1 : 0,
        definition: explained ? '$name 的一句话定义' : null,
        analogy: explained ? '类比' : null,
        example: explained ? '例子' : null,
        extension: explained ? '延伸A、延伸B' : null,
        tags: const ['AI'],
      );

  test('按天分组生成 Markdown', () {
    final day = DateTime(2026, 9, 22, 10);
    final md = ExportService.buildMarkdown(
      [t('向量数据库', day), t('RAG', day.add(const Duration(hours: 2)))],
      title: '# 2026-09',
    );
    expect(md.contains('# 2026-09'), isTrue);
    expect(md.contains('## 2026-09-22'), isTrue);
    expect(md.contains('### 向量数据库'), isTrue);
    expect(md.contains('**专业定义**'), isTrue);
    expect(md.contains('向量数据库 的一句话定义'), isTrue);
    expect(md.contains('**通俗解释**'), isTrue);
    expect(md.contains('#AI'), isTrue);
  });

  test('笔记与图片一并导出', () {
    final term = Term(
      id: 7,
      name: '余弦相似度',
      createdAt: DateTime(2026, 9, 22, 10),
      status: 1,
      definition: r'$\cos\theta=\frac{a\cdot b}{|a||b|}$',
      analogy: '两句话像不像，用夹角衡量',
    );
    final note = Note(
      id: 1,
      termId: 7,
      content: '我在推荐系统里见过',
      images: const ['/data/data/com.wenxu.wordlog/files/notes_img/a.jpg'],
      createdAt: DateTime(2026, 9, 22, 11),
      updatedAt: DateTime(2026, 9, 22, 11),
    );
    final md = ExportService.buildMarkdown([term], notes: {
      7: [note]
    });
    expect(md.contains('**我的笔记**'), isTrue);
    expect(md.contains('我在推荐系统里见过'), isTrue);
    expect(md.contains('![](images/a.jpg)'), isTrue);
  });

  test('未解释的词导出占位', () {
    final md = ExportService.buildMarkdown(
      [t('某个新词', DateTime(2026, 9, 22), explained: false)],
    );
    expect(md.contains('（待解释）'), isTrue);
  });

  test('同月多次导出按天去重合并', () {
    final day1 = DateTime(2026, 9, 22, 10);
    final day2 = DateTime(2026, 9, 23, 10);
    final first = ExportService.buildMarkdown([t('甲', day1)]);
    final second = ExportService.buildMarkdown([t('甲', day1), t('乙', day2)]);
    final merged = ExportService.merge(first, second);
    expect('### 甲'.allMatches(merged).length, 1);
    expect(merged.contains('### 乙'), isTrue);
  });
}
