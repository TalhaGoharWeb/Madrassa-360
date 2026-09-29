// Phase 8 repository-boundary unit tests.
//
// Implementation files under test:
//   lib/data/repositories/hostel_repository.dart
//   lib/data/repositories/transport_repository.dart
//   lib/data/repositories/certificate_repository.dart
//   lib/core/errors/app_exceptions.dart (BackendUnavailableException)
//
// CONTRACT: with no backend tables provisioned, every repository method
// must throw [BackendUnavailableException] — never return fake rows,
// never silently succeed. The UI renders its honest unavailable state
// off this exact signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/data/repositories/certificate_repository.dart';
import 'package:madrasa_360/data/repositories/hostel_repository.dart';
import 'package:madrasa_360/data/repositories/transport_repository.dart';

const _tenant = 't1';

HostelBuilding _building() => const HostelBuilding(
      id: 'b1',
      tenantId: _tenant,
      name: 'بلاک اے',
    );

TransportVehicle _vehicle() => const TransportVehicle(
      id: 'v1',
      tenantId: _tenant,
      plateNumber: 'LHR-1',
      vehicleType: 'بس',
    );

CertificateIssuance _issuance() => CertificateIssuance(
      id: 'c1',
      tenantId: _tenant,
      studentId: 's1',
      studentName: 'طالب',
      type: CertificateType.character,
      issuedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('BackendUnavailableException', () {
    test('is an AppException with the backend_unavailable code', () {
      const e = BackendUnavailableException();
      expect(e, isA<AppException>());
      expect(e.code, 'backend_unavailable');
    });

    test('Urdu message is honest and never a coming-soon promise', () {
      const e = BackendUnavailableException();
      expect(e.userMessageUr, isNotEmpty);
      expect(e.userMessageUr, isNot(contains('جلد')));
      expect(e.userMessageEn, isNot(contains('soon')));
    });
  });

  group('UnavailableHostelRepository', () {
    const repo = UnavailableHostelRepository();

    test('every read throws BackendUnavailableException', () {
      expect(() => repo.buildings(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.buildingById('b1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.rooms(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.roomById('r1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.beds(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.allocations(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.summary(_tenant),
          throwsA(isA<BackendUnavailableException>()));
    });

    test('every write throws BackendUnavailableException (no fake success)',
        () {
      expect(() => repo.saveBuilding(_building()),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteBuilding('b1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveRoom(const HostelRoom(
              id: 'r1', tenantId: _tenant, buildingId: 'b1', roomNo: '101')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteRoom('r1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveBed(const HostelBed(
              id: 'bd1', tenantId: _tenant, roomId: 'r1', bedNo: '1')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteBed('bd1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.allocate(HostelAllocation(
              id: 'a1',
              tenantId: _tenant,
              bedId: 'bd1',
              studentId: 's1',
              studentName: 'طالب',
              fromDate: DateTime(2026, 1, 1))),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.endAllocation('a1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
    });

    test('models carry tenant scoping fields', () {
      final b = _building();
      expect(b.tenantId, _tenant);
      expect(b.name, 'بلاک اے');
    });
  });

  group('UnavailableTransportRepository', () {
    const repo = UnavailableTransportRepository();

    test('every read throws BackendUnavailableException', () {
      expect(() => repo.vehicles(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.vehicleById('v1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.drivers(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.driverById('d1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.routes(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.routeById('r1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.stops('r1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.assignments(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.summary(_tenant),
          throwsA(isA<BackendUnavailableException>()));
    });

    test('every write throws BackendUnavailableException (no fake success)',
        () {
      expect(() => repo.saveVehicle(_vehicle()),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteVehicle('v1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveDriver(const TransportDriver(
              id: 'd1', tenantId: _tenant, name: 'ڈرائیور')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteDriver('d1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveRoute(
              const TransportRoute(id: 'r1', tenantId: _tenant, name: 'روٹ')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteRoute('r1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveStop(const TransportStop(
              id: 'st1', tenantId: _tenant, routeId: 'r1', name: 'اسٹاپ')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteStop('st1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(
          () => repo.saveAssignment(const TransportAssignment(
              id: 'a1', tenantId: _tenant, vehicleId: 'v1', routeId: 'r1')),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.deleteAssignment('a1', _tenant),
          throwsA(isA<BackendUnavailableException>()));
    });
  });

  group('UnavailableCertificateRepository', () {
    const repo = UnavailableCertificateRepository();

    test('history/nextSerialNumber/recordIssuance all throw', () {
      expect(() => repo.history(_tenant),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.nextSerialNumber(_tenant, CertificateType.character),
          throwsA(isA<BackendUnavailableException>()));
      expect(() => repo.recordIssuance(_issuance()),
          throwsA(isA<BackendUnavailableException>()));
    });

    test('CertificateType maps 1:1 to real report ids', () {
      expect(CertificateType.character.reportId, 'character_certificate');
      expect(CertificateType.transfer.reportId, 'transfer_certificate');
      expect(CertificateType.character.labelUr, 'کردار سرٹیفکیٹ');
      expect(CertificateType.transfer.labelUr, 'منتقلی سرٹیفکیٹ');
    });
  });
}
