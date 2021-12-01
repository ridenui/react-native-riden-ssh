// ReactNativeRidenSsh.m

#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ReactNativeRidenSsh, NSObject)

RCT_EXTERN_METHOD(connect:(NSString *) host
                  port: (nonnull NSNumber *) port
                  username: (NSString *) username
                  password: (NSString *) password
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(disconnect:(NSString *) connectionId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(isConnected:(NSString *) connectionId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(executeCommand:(NSString *) connectionId
                  command: (NSString *) command
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
