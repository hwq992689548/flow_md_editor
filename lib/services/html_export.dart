import 'package:markdown/markdown.dart' as md;

String exportSelfContainedHtml({
  required String title,
  required String markdownSource,
  required bool dark,
}) {
  final body = md.markdownToHtml(
    markdownSource,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final bg = dark ? '#1e1e1e' : '#ffffff';
  final fg = dark ? '#e6e6e6' : '#1a1a1a';
  final codeBg = dark ? '#2d2d2d' : '#f5f5f5';
  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${_escape(title)}</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0 auto;padding:32px;max-width:800px;background:$bg;color:$fg;line-height:1.6;}
pre,code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:$codeBg;}
pre{padding:12px;overflow:auto;border-radius:8px;}
code{padding:1px 4px;border-radius:4px;}
img{max-width:100%;}
table{border-collapse:collapse;width:100%;}
th,td{border:1px solid #8884;padding:6px 10px;}
blockquote{border-left:4px solid #8888;margin:0;padding:0 12px;color:#888;}
</style>
</head>
<body>
$body
</body>
</html>''';
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
