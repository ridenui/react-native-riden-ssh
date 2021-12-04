//
//  ReactNativeRidenSsh.swift
//  react-native-riden-ssh
//
//  Created by Nils Bergmann on 30/11/2021.
//

import Foundation
import NMSSH_riden

enum NATIVE_EVENTS: String {
    case resolve = "react-native-riden-ssh-resolve"
    case reject = "react-native-riden-ssh-reject"
    case onStdout = "react-native-riden-ssh-on-stdout"
    case onStderr = "react-native-riden-ssh-on-stderr"
}

extension NSLock {
    convenience init(initialLock: Bool) {
        self.init();
        if initialLock {
            self.lock();
        }
    }
}

struct SafeChannel {
    var channel: NMSSHChannel?;
    let lock: NSLock = NSLock(initialLock: true);
    
    mutating func close() {
        self.lock.lock();
        self.channel?.close();
        self.channel = nil;
        self.lock.unlock();
    }
}

@objc(ReactNativeRidenSsh)
class ReactNativeRidenSsh: RCTEventEmitter {
    
    var hasListeners: Bool = false;

    private var sessionMap: Dictionary<String, NMSSHSession> = [:];
    private var channelMap: Dictionary<String, Dictionary<String, SafeChannel>> = [:];
    
    let cancelLock = NSLock();
    
    @objc(connect:port:username:password:resolver:rejecter:)
    func connect(_ host: String, port: NSNumber, username: String, password: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let id = UUID().uuidString;
        sessionMap[id] = NMSSHSession(host: host, port: port.intValue, andUsername: username);
        if sessionMap[id]!.connect() {
            if sessionMap[id]!.authenticate(byPassword: password) {
                resolve(id);
                return;
            } else {
                reject("authentication_failed", "Authentication by password faild", nil);
            }
        } else {
            reject("connection_failed", "Connection to host failed", nil);
        }
        sessionMap[id] = nil;
    }
    
    @objc(disconnect:resolver:rejecter:)
    func disconnect(_ connectionId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        self.cancelLock.lock();
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            self.cancelLock.unlock();
            return;
        }
        sessionMap[connectionId]!.disconnect();
        resolve(nil);
        self.cancelLock.unlock();
    }
    
    @objc(isConnected:resolver:rejecter:)
    func isConnected(_ connectionId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        self.cancelLock.lock();
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            self.cancelLock.unlock();
            return;
        }
        resolve(sessionMap[connectionId]!.isConnected && sessionMap[connectionId]!.isAuthorized);
        self.cancelLock.unlock();
    }
    
    @objc(executeCommand:command:resolver:rejecter:)
    func executeCommand(_ connectionId: String, command: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        if self.sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            return;
        }
        if !self.sessionMap[connectionId]!.isConnected || !self.sessionMap[connectionId]!.isAuthorized {
            reject("not_connected", "The connection with this uuid \(connectionId) is not connected", nil);
            return;
        }
        DispatchQueue.init(label: "ssh-\(connectionId)-main").sync {
            var error: NSError?;
            var stderr: NSString?;
            var stdout: NSString?;
            
            self.sessionMap[connectionId]!.channel.execute(command, error: &error, stdout_out: &stdout, stderr_out: &stderr);
            if error != nil {
                let exitCodeString: String = error?.userInfo["exit_code"] as? String ?? "1";
                let exitCode = Int(exitCodeString) ?? 1;
                
                resolve([
                    "code": exitCode,
                    "signal": 1,
                    "stdout": String(stdout ?? NSString()).split(separator: "\n"),
                    "stderr": String(stderr ?? NSString()).split(separator: "\n"),
                ])
                return;
            }
            resolve([
                "code": 0,
                "signal": 0,
                "stdout": String(stdout ?? NSString()).split(separator: "\n"),
                "stderr": String(stderr ?? NSString()).split(separator: "\n")
            ])
        }
    }
    
    @objc(executeStreamCommand:command:eventCallback:)
    func executeStreamCommand(_ connectionId: String, command: String, eventCallback: RCTResponseSenderBlock) {
        let channelId = UUID().uuidString;
        let functionId = UUID().uuidString;
                
        eventCallback([functionId, channelId]);
        
        let eventSendCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            if self.hasListeners {
                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
            }
        }
    
        let resolverCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            // clean up
            self.cancelLock.lock();
            if self.sessionMap[connectionId] != nil {
                if self.channelMap[connectionId]?[channelId] != nil {
                    self.channelMap[connectionId]![channelId]!.close();
                }
            }
            if self.hasListeners {
                eventSendCallback(eventName, argArray);
            }
            self.cancelLock.unlock();
        };
        
        if self.sessionMap[connectionId] == nil {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "no_connection_with_this_id", "message": "No connection with the uuid \(connectionId)"]
            ]);
            return;
        }
        
        if !self.sessionMap[connectionId]!.isConnected || !self.sessionMap[connectionId]!.isAuthorized {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "not_connected", "message": "The connection with this uuid \(connectionId) is not connected"]
            ]);
            return;
        }
        
        if self.channelMap[connectionId] == nil {
            self.channelMap[connectionId] = [:];
        }
        
        self.channelMap[connectionId]![channelId] = SafeChannel(channel: NMSSHChannel(session: self.sessionMap[connectionId]!));
        
        let queue = DispatchQueue.init(label: "ssh-\(connectionId)-\(channelId)");
        
        queue.async {
            var error: Error?;
            
            let streamBridgeDelegate = StreamBridge { stdout in
                eventSendCallback(.onStdout, [stdout]);
            } onStderr: { stder in
                eventSendCallback(.onStderr, [stder]);
            } onExit: { exitCode in
                if error != nil {
                    resolverCallback(NATIVE_EVENTS.reject, [
                        [
                            "id": "nmssh_error",
                            "message": error?.localizedDescription
                        ]
                    ]);
                    return
                }
                resolverCallback(NATIVE_EVENTS.resolve, [
                    [
                        "code": exitCode,
                        "signal": 0,
                    ]
                ])
            } onError: { err in
                error = err;
            }
            
            let streamBridge = NMSSHChannelStream();
            
            streamBridge.delegate = streamBridgeDelegate;
            
            queue.async {
                self.channelMap[connectionId]![channelId]!.channel?.executeStream(command, channelStream: streamBridge);
            }
            
            self.channelMap[connectionId]![channelId]?.lock.unlock();
        }
    }
    
    @objc(executeCommandCancelable:command:eventCallback:)
    func executeCommandCancelable(_ connectionId: String, command: String, eventCallback: RCTResponseSenderBlock) {
        let channelId = UUID().uuidString;
        let functionId = UUID().uuidString;
                
        eventCallback([functionId, channelId]);
        
        let resolverCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            self.cancelLock.lock();
            // clean up
            if self.sessionMap[connectionId] != nil {
                if self.channelMap[connectionId]?[channelId] != nil {
                    self.channelMap[connectionId]![channelId]!.close();
                }
            }
            if self.hasListeners {
                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
            }
            self.cancelLock.unlock();
        };
        
        if self.sessionMap[connectionId] == nil {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "no_connection_with_this_id", "message": "No connection with the uuid \(connectionId)"]
            ]);
            return;
        }
        
        if !self.sessionMap[connectionId]!.isConnected || !self.sessionMap[connectionId]!.isAuthorized {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "not_connected", "message": "The connection with this uuid \(connectionId) is not connected"]
            ]);
            return;
        }
        
        if self.channelMap[connectionId] == nil {
            self.channelMap[connectionId] = [:];
        }
        
        self.channelMap[connectionId]![channelId] = SafeChannel(channel: NMSSHChannel(session: self.sessionMap[connectionId]!));
                
        DispatchQueue.init(label: "ssh-\(connectionId)-\(channelId)").async {
            var error: NSError?;
            var stderr: NSString?;
            var stdout: NSString?;
            
            
            self.channelMap[connectionId]![channelId]!.channel!.execute(command, error: &error, stdout_out: &stdout, stderr_out: &stderr);
            
            self.channelMap[connectionId]![channelId]?.lock.unlock();
            
            if error != nil {
                let exitCodeString: String = error?.userInfo["exit_code"] as? String ?? "1";
                let exitCode = Int(exitCodeString) ?? 1;
                                            
                resolverCallback(NATIVE_EVENTS.resolve, [
                    [
                        "code": exitCode,
                        "signal": 1,
                        "stdout": String(stdout ?? NSString()).split(separator: "\n"),
                        "stderr": String(stderr ?? NSString()).split(separator: "\n"),
                    ]
                ])
                
                return;
            }
            resolverCallback(NATIVE_EVENTS.resolve, [
                [
                    "code": 0,
                    "signal": 0,
                    "stdout": String(stdout ?? NSString()).split(separator: "\n"),
                    "stderr": String(stderr ?? NSString()).split(separator: "\n")
                ]
            ])
        }
    }
    
    @objc(cancelCommand:channelId:resolver:rejecter:)
    func cancelCommand(_ connectionId: String, channelId: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        self.cancelLock.lock();
        print("Received cancel request for channel \(channelId) on \(connectionId)");
        if self.sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            self.cancelLock.unlock();
            return;
        }
        if !self.sessionMap[connectionId]!.isConnected || !self.sessionMap[connectionId]!.isAuthorized {
            reject("not_connected", "The connection with this uuid \(connectionId) is not connected", nil);
            self.cancelLock.unlock();
            return;
        }
        if self.channelMap[connectionId]?[channelId] == nil {
            reject("no_channel_with_this_id", "There is no channel with the id \(channelId)", nil);
            self.cancelLock.unlock();
            return;
        }
        self.channelMap[connectionId]![channelId]!.close();
        resolve(nil);
        self.cancelLock.unlock();
    }
    
    @objc
    override static func requiresMainQueueSetup() -> Bool{
        return false;
    }
    
    override func supportedEvents() -> [String]! {
        return [NATIVE_EVENTS.resolve, NATIVE_EVENTS.reject, NATIVE_EVENTS.onStderr, NATIVE_EVENTS.onStdout].map({ $0.rawValue })
    }
    
    override func stopObserving() {
        hasListeners = false;
    }
    
    override func startObserving() {
        hasListeners = true;
    }
    
}
