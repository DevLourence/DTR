// ignore_for_file: prefer_const_constructors
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/dtr_entry.dart';

class PdfService {
  static Future<Uint8List> generateForm48(
    MonthlyDtr dtr, {
    String inCharge = '', 
    bool singleForm = false,
    TimeOfDay? amIn,
    TimeOfDay? amOut,
    TimeOfDay? pmIn,
    TimeOfDay? pmOut,
  }) async {
    return generateBulkForm48(
      [dtr], 
      inCharge: inCharge, 
      duplicateSamePerson: !singleForm, 
      singleForm: singleForm,
      amIn: amIn,
      amOut: amOut,
      pmIn: pmIn,
      pmOut: pmOut,
    );
  }

  static Future<Uint8List> generateBulkForm48(
    List<MonthlyDtr> dtrs, {
    String inCharge = '', 
    bool duplicateSamePerson = false, 
    bool singleForm = false,
    TimeOfDay? amIn,
    TimeOfDay? amOut,
    TimeOfDay? pmIn,
    TimeOfDay? pmOut,
  }) async {
    final pdf = pw.Document();

    // Group dtrs in pairs
    int step = (duplicateSamePerson || singleForm) ? 1 : 2;
    for (int i = 0; i < dtrs.length; i += step) {
      final dtr1 = dtrs[i];
      final dtr2 = (duplicateSamePerson && !singleForm) ? dtr1 : ((!singleForm && i + 1 < dtrs.length) ? dtrs[i + 1] : null);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            if (singleForm) {
              return pw.Align(
                alignment: pw.Alignment.topLeft,
                child: pw.Container(
                  width: PdfPageFormat.a4.width / 2 - 20,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(style: pw.BorderStyle.dashed, width: 0.5),
                  ),
                  child: _buildDtrForm(dtr1, inCharge, amIn: amIn, amOut: amOut, pmIn: pmIn, pmOut: pmOut),
                ),
              );
            }
            return pw.Stack(
              children: [
                // Outer dashed border and middle vertical divider
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(style: pw.BorderStyle.dashed, width: 0.5),
                  ),
                ),
                pw.Center(
                  child: pw.Container(
                    width: 0.5,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(left: pw.BorderSide(style: pw.BorderStyle.dashed, width: 0.5)),
                    ),
                  ),
                ),
                // Two forms side by side
                pw.Row(
                  children: [
                    pw.Expanded(child: _buildDtrForm(dtr1, inCharge, amIn: amIn, amOut: amOut, pmIn: pmIn, pmOut: pmOut)),
                    pw.Expanded(child: dtr2 != null ? _buildDtrForm(dtr2, inCharge, amIn: amIn, amOut: amOut, pmIn: pmIn, pmOut: pmOut) : pw.SizedBox()),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _buildDtrForm(
    MonthlyDtr dtr, 
    String inCharge, {
    TimeOfDay? amIn,
    TimeOfDay? amOut,
    TimeOfDay? pmIn,
    TimeOfDay? pmOut,
  }) {
    // Priority: Individual DTR settings -> Global settings
    final effectiveInCharge = dtr.supervisor ?? inCharge;
    
    TimeOfDay parse(String? s, TimeOfDay? fallback) {
      if (s == null || !s.contains(':')) return fallback ?? const TimeOfDay(hour: 0, minute: 0);
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    final effectiveAmIn = parse(dtr.amInTime, amIn);
    final effectiveAmOut = parse(dtr.amOutTime, amOut);
    final effectivePmIn = parse(dtr.pmInTime, pmIn);
    final effectivePmOut = parse(dtr.pmOutTime, pmOut);

    int totalMonthUndertime = 0;
    for (int day = 1; day <= 31; day++) {
      final entry = dtr.entries[day];
      if (entry != null) {
        totalMonthUndertime += _calculateUndertime(entry, effectiveAmIn, effectiveAmOut, effectivePmIn, effectivePmOut);
      }
    }
    final totalHours = totalMonthUndertime ~/ 60;
    final totalMins = totalMonthUndertime % 60;

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text('Civil Service Form No. 48', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8)),
          ),
          pw.SizedBox(height: 2),
          pw.Text('DAILY TIME RECORD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text('-----o0o-----', style: pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 15),

          pw.Container(
            width: 180,
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child: pw.Text(dtr.name.toUpperCase(), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('(Name)', style: pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 8),

          pw.Row(
            children: [
              pw.Text('For the month of', style: pw.TextStyle(fontSize: 8)),
              pw.Expanded(
                child: pw.Container(
                  margin: pw.EdgeInsets.only(left: 5),
                  decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  child: pw.Text('${dtr.monthName.toUpperCase()} ${dtr.year}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 5),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Official hours for arrival', style: pw.TextStyle(fontSize: 7)),
                    pw.Text('and departure', style: pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ),
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Container(height: 0.5, color: PdfColors.black)),
                        pw.SizedBox(width: 5),
                        pw.Text('Regular days', style: pw.TextStyle(fontSize: 6)),
                      ]
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Container(height: 0.5, color: PdfColors.black)),
                        pw.SizedBox(width: 5),
                        pw.Text('Saturdays', style: pw.TextStyle(fontSize: 6)),
                      ]
                    ),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 8),

          // Table
          pw.Table(
            columnWidths: {
              0: pw.FixedColumnWidth(22),
              1: pw.FlexColumnWidth(),
              2: pw.FlexColumnWidth(),
              3: pw.FlexColumnWidth(),
            },
            border: pw.TableBorder.all(width: 0.5),
            children: [
              pw.TableRow(
                children: [
                  pw.Container(child: pw.Text('Day', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8)), padding: pw.EdgeInsets.all(1)),
                  pw.Column(children: [
                    pw.Text('A.M.', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Container(child: pw.Text('Arrival', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))))),
                      pw.Expanded(child: pw.Container(child: pw.Text('Departure', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), left: pw.BorderSide(width: 0.5))))),
                    ])
                  ]),
                  pw.Column(children: [
                    pw.Text('P.M.', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Container(child: pw.Text('Arrival', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))))),
                      pw.Expanded(child: pw.Container(child: pw.Text('Departure', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), left: pw.BorderSide(width: 0.5))))),
                    ])
                  ]),
                  pw.Column(children: [
                    pw.Text('Undertime', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Container(child: pw.Text('Hours', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))))),
                      pw.Expanded(child: pw.Container(child: pw.Text('Minutes', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6)), decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5), left: pw.BorderSide(width: 0.5))))),
                    ])
                  ]),
                ],
              ),

              // Days 1-31
              ...List.generate(31, (index) {
                final day = index + 1;
                final entry = dtr.entries[day];
                
                // Calculate Undertime
                int undertimeMinutes = 0;
                if (entry != null) {
                  undertimeMinutes = _calculateUndertime(entry, effectiveAmIn, effectiveAmOut, effectivePmIn, effectivePmOut);
                }
                
                final utHours = undertimeMinutes ~/ 60;
                final utMins = undertimeMinutes % 60;

                return pw.TableRow(
                  children: [
                    pw.Container(child: pw.Text('$day', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7)), padding: pw.EdgeInsets.all(0.5)),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Container(child: pw.Text(entry?.amArrivalStr ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)), padding: pw.EdgeInsets.all(0.5))),
                        pw.Expanded(child: pw.Container(child: pw.Text(entry?.amDepartureStr ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7)), padding: pw.EdgeInsets.all(0.5), decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5))))),
                      ],
                    ),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Container(child: pw.Text(entry?.pmArrivalStr ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7)), padding: pw.EdgeInsets.all(0.5))),
                        pw.Expanded(child: pw.Container(child: pw.Text(entry?.pmDepartureStr ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)), padding: pw.EdgeInsets.all(0.5), decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5))))),
                      ],
                    ),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Container(child: pw.Text(utHours > 0 ? '$utHours' : '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7)), padding: pw.EdgeInsets.all(0.5))),
                        pw.Expanded(child: pw.Container(child: pw.Text(utMins > 0 ? '$utMins' : '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7)), padding: pw.EdgeInsets.all(0.5), decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5))))),
                      ],
                    ),
                  ],
                );
              }),

              pw.TableRow(
                children: [
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.Container(
                    child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    padding: pw.EdgeInsets.all(1),
                  ),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          child: pw.Text(
                            totalHours > 0 ? '$totalHours' : '',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                          padding: pw.EdgeInsets.all(0.5),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          child: pw.Text(
                            totalMins > 0 ? '$totalMins' : '',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                          padding: pw.EdgeInsets.all(0.5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border(left: pw.BorderSide(width: 0.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            ],
          ),

          pw.SizedBox(height: 8),
          pw.Text('I certify on my honor that the above is a true and correct report of the \nhours of work performed, record of which was made daily at the time \nof arrival and departure from office.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 6.5, fontStyle: pw.FontStyle.italic),
          ),

          pw.SizedBox(height: 15),
          pw.Container(width: 180, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
          pw.SizedBox(height: 10),
          pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('VERIFIED as to the prescribed office hours:', style: pw.TextStyle(fontSize: 6.5, fontStyle: pw.FontStyle.italic))),
          pw.SizedBox(height: 10),
          pw.Container(
            width: 180, 
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child: pw.Text(effectiveInCharge.toUpperCase(), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('In Charge', style: pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );
  }

  static int _calculateUndertime(DtrEntry entry, TimeOfDay amIn, TimeOfDay amOut, TimeOfDay pmIn, TimeOfDay pmOut) {
    int totalUndertime = 0;

    // AM In (Late)
    if (entry.amArrival != null) {
      final actualIn = entry.amArrival!;
      if (actualIn.hour > amIn.hour || (actualIn.hour == amIn.hour && actualIn.minute > amIn.minute)) {
        totalUndertime += (actualIn.hour - amIn.hour) * 60 + (actualIn.minute - amIn.minute);
      }
    }

    // AM Out (Early Departure)
    if (entry.amDeparture != null) {
      final actualOut = entry.amDeparture!;
      if (actualOut.hour < amOut.hour || (actualOut.hour == amOut.hour && actualOut.minute < amOut.minute)) {
        totalUndertime += (amOut.hour - actualOut.hour) * 60 + (amOut.minute - actualOut.minute);
      }
    }

    // PM In (Late)
    if (entry.pmArrival != null) {
      final actualIn = entry.pmArrival!;
      if (actualIn.hour > pmIn.hour || (actualIn.hour == pmIn.hour && actualIn.minute > pmIn.minute)) {
        totalUndertime += (actualIn.hour - pmIn.hour) * 60 + (actualIn.minute - pmIn.minute);
      }
    }

    // PM Out (Early Departure)
    if (entry.pmDeparture != null) {
      final actualOut = entry.pmDeparture!;
      if (actualOut.hour < pmOut.hour || (actualOut.hour == pmOut.hour && actualOut.minute < pmOut.minute)) {
        totalUndertime += (pmOut.hour - actualOut.hour) * 60 + (pmOut.minute - actualOut.minute);
      }
    }

    return totalUndertime;
  }
}
