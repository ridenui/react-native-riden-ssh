// ReactNativeRidenSsh.m

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_REMAP_MODULE(SSH, ReactNativeRidenSsh, RCTEventEmitter)

    RCT_EXTERN_METHOD(connect:(NSString *) host
                      port: (nonnull NSNumber *)port
                      username: (NSString *)username
                      password: (NSString *)password
                      resolver: (RCTPromiseResolveBlock)resolve
                      rejecter: (RCTPromiseRejectBlock)reject)

    RCT_EXTERN_METHOD(disconnect: (NSString *)connectionId
                      resolver: (RCTPromiseResolveBlock)resolve
                      rejecter: (RCTPromiseRejectBlock)reject)

    RCT_EXTERN_METHOD(isConnected: (NSString *)connectionId
                      resolver: (RCTPromiseResolveBlock)resolve
                      rejecter: (RCTPromiseRejectBlock)reject)

    RCT_EXTERN_METHOD(executeCommand: (NSString *)connectionId
                      command: (NSString *)command
                      resolver: (RCTPromiseResolveBlock)resolve
                      rejecter: (RCTPromiseRejectBlock)reject)

    RCT_EXTERN_METHOD(executeCommandCancelable: (NSString *)connectionId
                      command: (NSString *)command
                      eventCallback: (RCTResponseSenderBlock)eventCallback)

    RCT_EXTERN_METHOD(cancelCommand: (NSString *)connectionId
                      channelId: (NSString *)channelId
                      resolver: (RCTPromiseResolveBlock)resolve
                      rejecter: (RCTPromiseRejectBlock)reject)

    RCT_EXTERN_METHOD(executeStreamCommand: (NSString *)connectionId
                  command: (NSString *)command
                  eventCallback: (RCTResponseSenderBlock)eventCallback)
@end
