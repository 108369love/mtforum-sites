import 'package:flutter/material.dart';

/// 页面路由的统一入口。
///
/// 手势导航（左右拖动切换页面）已经下线：它需要在 Navigator 外层铺一层
/// 全屏横向手势，和「长按选字、拖选择手柄、图片左右翻页、表格横向滚动」
/// 一直在抢同一串指针事件，修一处冒一处。收益不抵成本，回退到普通路由。
///
/// 保留 [appRoute] / [noSwipeRoute] 两个函数，是因为全项目几十处调用点
/// 都用它们；底层现在就是普通的 [MaterialPageRoute]，`gestures` 参数仅为
/// 兼容旧调用保留，不再有实际作用。
Route<T> appRoute<T>({
  required WidgetBuilder builder,
  bool gestures = true,
  RouteSettings? settings,
}) =>
    MaterialPageRoute<T>(builder: builder, settings: settings);

/// 曾经用来标记「编辑、登录、图片浏览」这类不参与手势的页面。
/// 手势导航下线后与 [appRoute] 完全一致。
Route<T> noSwipeRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) =>
    appRoute<T>(builder: builder, settings: settings);
