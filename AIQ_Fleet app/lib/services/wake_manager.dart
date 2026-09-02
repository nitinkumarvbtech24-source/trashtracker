import 'package:wakelock_plus/wakelock_plus.dart';
import 'camera_service.dart';
import 'telemetry_service.dart';

class WakeManager {
  static void update() {
    bool isNav = TelemetryService().isNavigating;
    bool isCam = CameraService().isAutoMode || 
                 CameraService().isAutoCapturing || 
                 CameraService().isTrainingCapturing ||
                 CameraService().isTrainingMode;

    if (isNav || isCam) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }
}
