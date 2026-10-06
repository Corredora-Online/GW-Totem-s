import '../../services/nfc/nfc_service.dart';
import '../../services/scanner/scanner_service.dart';
import '../../services/speaker/speaker_service.dart';

class MockScannerService implements ScannerService {
  @override
  Stream<String> get codes => const Stream<String>.empty();
}

class MockNfcService implements NfcService {
  @override
  Future<String?> readTag() async => null;
}

class MockSpeakerService implements SpeakerService {
  @override
  Future<void> playSuccess() async {}
}
