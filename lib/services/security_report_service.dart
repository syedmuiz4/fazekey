import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/access_log.dart';

class SecurityReportService {
  Future<File> writePdfReport(List<AccessLog> logs) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'facekey-security-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(p.join(dir.path, fileName));
    final lines = [
      'FaceKey Security Log Report',
      'Generated ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
      '',
      for (final log in logs.take(80))
        '${DateFormat('EEE HH:mm').format(log.timestamp)} | ${log.status.toUpperCase()} | ${log.userName} | ${log.areaName} | ${log.reason}',
    ];
    await file.writeAsBytes(_simplePdf(lines), flush: true);
    return file;
  }

  List<int> _simplePdf(List<String> lines) {
    final objects = <String>[];
    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    objects.add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

    final content = StringBuffer('BT\n/F1 11 Tf\n40 760 Td\n14 TL\n');
    for (final line in lines) {
      content.writeln('(${_escape(line)}) Tj');
      content.writeln('T*');
    }
    content.write('ET');
    final stream = content.toString();
    objects.add('<< /Length ${latin1.encode(stream).length} >>\nstream\n$stream\nendstream');

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(latin1.encode(buffer.toString()).length);
      buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xrefOffset = latin1.encode(buffer.toString()).length;
    buffer.write('xref\n0 ${objects.length + 1}\n');
    buffer.write('0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF');
    return latin1.encode(buffer.toString());
  }

  String _escape(String value) => value.replaceAll('\\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
}
