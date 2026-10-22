#import "AirbuildPlugin.h"

@implementation AirbuildPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // The method channel is registered so the Dart side can call it without
    // throwing MissingPluginException. On iOS the install flow is handled
    // entirely in Dart via url_launcher, so no native methods are needed.
    FlutterMethodChannel *channel =
        [FlutterMethodChannel methodChannelWithName:@"dev.airbuild.airbuild/install"
                                      binaryMessenger:registrar.messenger];
    AirbuildPlugin *instance = [[AirbuildPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"installApk" isEqualToString:call.method]) {
        // iOS does not support APK install — this is a no-op.
        // The Dart side uses url_launcher to open the install URL in Safari.
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end
