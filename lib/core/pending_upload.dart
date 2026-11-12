/// 还没传到服务器、要跟着发帖请求一起提交的图片 / 附件。
///
/// 站点用的是 comiis 手机模板，发帖表单里直接放
/// `<input type="file" name="Filedata">`，靠表单本身把文件带上去，
/// 不走 `misc.php?mod=swfupload`。那种模板的页面上没有 swfupload 需要的
/// hash（它由站点私钥算出来，客户端推不出来），所以拿不到凭证时只能照
/// 网页的做法：把文件塞进发帖请求里一起送。
library;

class PendingUpload {
  const PendingUpload({
    required this.filename,
    required this.bytes,
    this.image = true,
  });

  final String filename;
  final List<int> bytes;
  final bool image;

  /// 表单里的字段名。Discuz 手机模板用的就是 `Filedata`，图片和附件都一样，
  /// 具体归类靠 `type=image` 之类的其它字段，不靠字段名。
  String get field => 'Filedata';
}
