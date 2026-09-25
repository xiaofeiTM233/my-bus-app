import 'package:flutter/material.dart';

import '../api/mybus_client.dart';

/// 统一把异常转成用户可读的 SnackBar。
void showError(BuildContext context, Object e) {
  String msg;
  if (e is MyBusException) {
    msg = e.cityUnsupported
        ? '该城市暂不提供公交查询（status=-2），请更换城市'
        : e.blocked
            ? '请求被接口风控拦截，请稍后重试'
            : e.msg;
  } else {
    msg = e.toString();
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}
