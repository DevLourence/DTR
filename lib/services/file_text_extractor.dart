import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:docx_to_text/docx_to_text.dart';

class FileTextExtractor {
  static Future<String> extractText(File file) async {
    final extension = file.path.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return await _extractFromPdf(file);
      case 'xlsx':
      case 'xls':
        return await _extractFromExcel(file);
      case 'docx':
        return await _extractFromDocx(file);
      case 'txt':
      case 'dat':
      case 'csv':
        return await file.readAsString();
      default:
        // Attempt to read as string for unknown types
        try {
          return await file.readAsString();
        } catch (e) {
          throw Exception('Unsupported file format or file is binary: $extension');
        }
    }
  }

  static Future<String> _extractFromPdf(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final String text = extractor.extractText();
    document.dispose();
    return text;
  }

  static Future<String> _extractFromExcel(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    
    // Check if it's SpreadsheetML (XML)
    try {
      final header = String.fromCharCodes(bytes.take(100));
      if (header.contains('<?xml') || header.contains('<Workbook')) {
        return await file.readAsString();
      }
    } catch (_) {}

    final excel = Excel.decodeBytes(bytes);
    final StringBuffer buffer = StringBuffer();

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      for (var row in sheet.rows) {
        final rowData = row.map((cell) => cell?.value?.toString() ?? '').join('\t');
        buffer.writeln(rowData);
      }
    }
    return buffer.toString();
  }

  static Future<String> _extractFromDocx(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    return docxToText(bytes);
  }
}
