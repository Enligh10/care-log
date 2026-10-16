import 'package:care_log/models.dart';
import 'package:care_log/ui/journal_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregates a day of logs', () {
    final day = DateTime(2026, 10, 16, 8);
    final logs = [
      LogEntry(id: '1', kind: LogKind.med, at: day, byName: 'Dani', medId: 'mp'),
      LogEntry(id: '2', kind: LogKind.med, at: day.add(const Duration(hours: 9)), byName: 'Dani', medId: 'mp'),
      LogEntry(id: '3', kind: LogKind.vitals, at: day, byName: 'Dani', sys: 120, dia: 80, hr: 90),
      LogEntry(id: '4', kind: LogKind.vitals, at: day, byName: 'Dani', sys: 110, dia: 70, tempF: 100.6),
      LogEntry(id: '5', kind: LogKind.symptom, at: day, byName: 'Dani', symptomName: 'Nausea', severity: 3),
      LogEntry(id: '6', kind: LogKind.symptom, at: day, byName: 'Dani', symptomName: 'Nausea', severity: 6),
    ];
    final agg = aggregate(logs)[16]!;
    expect(agg.doses['mp'], 2);
    expect(agg.avgSys, 115);
    expect(agg.avgDia, 75);
    expect(agg.avgHr, 90);
    expect(agg.maxTemp, 100.6);
    expect(agg.symptomMax['Nausea'], 6);
  });

  test('blood pressure categories', () {
    expect(bpCategory(115, 75).$2, 'Normal');
    expect(bpCategory(125, 75).$2, 'Elevated');
    expect(bpCategory(132, 75).$2, 'High 1');
    expect(bpCategory(145, 92).$2, 'High 2');
    expect(bpCategory(85, 55).$2, 'Low');
  });

  test('temperature categories', () {
    expect(tempCategory(98.6).$2, 'Normal');
    expect(tempCategory(99.8).$2, 'Raised');
    expect(tempCategory(100.4).$2, 'Fever');
  });
}
