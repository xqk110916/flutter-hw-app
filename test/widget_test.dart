import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_hw_app/main.dart';

void main() {
  testWidgets('shows import empty state', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const InventoryApp());
    await tester.pumpAndSettle();

    expect(find.text('实物盘存'), findsOneWidget);
    expect(find.text('未找到本机工作文件'), findsOneWidget);
    expect(find.text('导入 JSON 文件'), findsOneWidget);
  });
}
