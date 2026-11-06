import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

Future<MultipartFile> multipartFromXFile(
  XFile file, {
  required String filename,
  required String contentType,
}) async {
  return MultipartFile.fromBytes(
    await file.readAsBytes(),
    filename: filename,
    contentType: MediaType.parse(contentType),
  );
}
