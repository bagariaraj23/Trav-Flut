String _injectTransformations(
  String url, {
  required List<String> transformations,
}) {
  if (!url.contains("/upload/")) return url;

  const uploadToken = "/upload/";
  final uploadIndex = url.indexOf(uploadToken);
  if (uploadIndex == -1) return url;

  final prefix = url.substring(0, uploadIndex + uploadToken.length);
  final suffix = url.substring(uploadIndex + uploadToken.length);

  final slashIndex = suffix.indexOf('/');
  if (slashIndex == -1) return url;

  final firstSegment = suffix.substring(0, slashIndex);
  final rest = suffix.substring(slashIndex); // includes '/'
  final versionRegex = RegExp(r"^v\d+$");
  final transformSet = <String>{};

  if (!versionRegex.hasMatch(firstSegment)) {
    transformSet.addAll(firstSegment.split(',').where((v) => v.isNotEmpty));
    transformSet.addAll(transformations.where((v) => v.isNotEmpty));
    if (transformSet.isEmpty) {
      return '$prefix$firstSegment$rest';
    }
    final newSegment = transformSet.join(',');
    return '$prefix$newSegment$rest';
  } else {
    transformSet.addAll(transformations.where((v) => v.isNotEmpty));
    if (transformSet.isEmpty) {
      return url;
    }
    final newSegment = transformSet.join(',');
    return '$prefix$newSegment/$suffix';
  }
}

String buildOptimizedImageUrl(
  String url, {
  int? width,
  int? height,
}) {
  final transformations = <String>["f_auto", "q_auto"];
  if (width != null) transformations.add("w_$width");
  if (height != null) transformations.add("h_$height");
  transformations.add("c_limit");
  return _injectTransformations(url, transformations: transformations);
}

String buildOptimizedVideoUrl(
  String url, {
  int? maxWidth,
}) {
  final transformations = <String>["f_auto", "q_auto", "vc_auto"];
  if (maxWidth != null) transformations.add("w_$maxWidth");
  return _injectTransformations(url, transformations: transformations);
}

String buildVideoThumbnailUrl(
  String url, {
  int? maxWidth,
}) {
  final transformations = <String>["f_auto", "q_auto", "so_0"];
  if (maxWidth != null) transformations.add("w_$maxWidth");
  final transformed =
      _injectTransformations(url, transformations: transformations);

  try {
    final uri = Uri.parse(transformed);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isEmpty) return transformed;

    final lastIndex = segments.length - 1;
    final filename = segments[lastIndex];
    final dotIndex = filename.lastIndexOf(".");
    final baseName = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
    segments[lastIndex] = "$baseName.jpg";

    return uri.replace(pathSegments: segments, queryParameters: null).toString();
  } catch (_) {
    return transformed;
  }
}

