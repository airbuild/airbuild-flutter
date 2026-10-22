/// AirBuild Distribution SDK for Flutter.
///
/// Usage:
///
/// ```dart
/// import 'package:airbuild/airbuild.dart';
///
/// void main() {
///   AirBuild.configure(distributionKey: 'dk_a1b2c3d4e5f6');
///   runApp(MyApp());
/// }
/// ```
///
/// Then, anywhere in your app:
///
/// ```dart
/// await AirBuild.checkForUpdates(currentVersion: '1.0.0');
/// ```
library airbuild;

export 'src/airbuild.dart';
export 'src/airbuild_config.dart';
export 'src/update_info.dart';
export 'src/update_dialog.dart';
