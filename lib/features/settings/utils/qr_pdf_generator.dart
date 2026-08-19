import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../data/models/device_model.dart';

class QrPdfGenerator {
  static Future<void> generateAndPrintA4(List<DeviceModel> devices) async {
    final pdf = pw.Document();

    final ttf = await PdfGoogleFonts.robotoRegular();

    // 2x2 cm size. 1 cm = 28.346 points
    const double qrSize = 2 * 28.346;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(level: 0, child: pw.Text('Cihaz Karekodları', style: pw.TextStyle(font: ttf))),
            pw.Wrap(
              spacing: 20,
              runSpacing: 30,
              children: devices.map((device) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: qrSize,
                      height: qrSize,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: 'homecare://device/${device.id}',
                        width: qrSize,
                        height: qrSize,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(device.name, style: pw.TextStyle(fontSize: 10, font: ttf)),
                  ],
                );
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
