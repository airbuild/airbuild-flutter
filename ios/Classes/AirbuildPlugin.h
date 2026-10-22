#import <Flutter/Flutter.h>

/// AirbuildPlugin — Flutter platform plugin for AirBuild SDK (iOS).
///
/// On iOS, the update flow opens the install URL in Safari via the
/// url_launcher Dart package, so the native side is minimal — it just
/// registers the plugin so the method channel is available.
@interface AirbuildPlugin : NSObject<FlutterPlugin>
@end
