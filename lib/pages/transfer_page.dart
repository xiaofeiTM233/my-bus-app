import 'package:flutter/material.dart';

/// 换乘规划占位：接口（CMD 111/118）尚未逆向验证，M3 处理。
class TransferPage extends StatelessWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('换乘规划')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('换乘接口尚未验证\n将在后续版本提供', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
