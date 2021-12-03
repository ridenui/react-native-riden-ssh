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
}

@objc(ReactNativeRidenSsh)
class ReactNativeRidenSsh: RCTEventEmitter {
    
    var hasListeners: Bool = false;

    private var sessionMap: Dictionary<String, NMSSHSession> = [:];
    private var channelMap: Dictionary<String, Dictionary<String, NMSSHChannel>> = [:];
    
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
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            return;
        }
        sessionMap[connectionId]!.disconnect();
        resolve(nil);
    }
    
    @objc(isConnected:resolver:rejecter:)
    func isConnected(_ connectionId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            return;
        }
        resolve(sessionMap[connectionId]!.isConnected && sessionMap[connectionId]!.isAuthorized);
    }
    
    @objc(executeCommand:command:resolver:rejecter:)
    func executeCommand(_ connectionId: String, command: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            return;
        }
        if !sessionMap[connectionId]!.isConnected || !sessionMap[connectionId]!.isAuthorized {
            reject("not_connected", "The connection with this uuid \(connectionId) is not connected", nil);
            return;
        }
        var error: NSError?;
        var stderr: NSString?;
        var stdout: NSString?;
        sessionMap[connectionId]!.channel.execute(command, error: &error, stdout_out: &stdout, stderr_out: &stderr);
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
    
    @objc(executeCommandCancelable:command:eventCallback:)
    func executeCommandCancelable(_ connectionId: String, command: String, eventCallback: RCTResponseSenderBlock) {
        let channelId = UUID().uuidString;
        let functionId = UUID().uuidString;
        
        eventCallback([functionId, channelId]);
        
        let resolverCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
//            print("send event \(eventName)");
            if self.hasListeners {
                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
            }
//            } else {
//                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
//                print("No listener")
//            }
        };
        
        if sessionMap[connectionId] == nil {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "no_connection_with_this_id", "message": "No connection with the uuid \(connectionId)"]
            ]);
            return;
        }
        
        if !sessionMap[connectionId]!.isConnected || !sessionMap[connectionId]!.isAuthorized {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "not_connected", "message": "The connection with this uuid \(connectionId) is not connected"]
            ]);
            return;
        }
        
        if channelMap[connectionId] == nil {
            channelMap[connectionId] = [:];
        }
        
        channelMap[connectionId]![channelId] = NMSSHChannel(session: sessionMap[connectionId]!);
                        
        var error: NSError?;
        var stderr: NSString?;
        var stdout: NSString?;
        channelMap[connectionId]![channelId]!.execute(command, error: &error, stdout_out: &stdout, stderr_out: &stderr);
        if error != nil {
            let exitCodeString: String = error?.userInfo["exit_code"] as? String ?? "1";
            let exitCode = Int(exitCodeString) ?? 1;
            
//            print("Call with error \(stderr) \(stdout)")
            
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
    
    @objc(cancelCommand:channelId:resolver:rejecter:)
    func cancelCommand(_ connectionId: String, channelId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No connection with the uuid \(connectionId)", nil);
            return;
        }
        if !sessionMap[connectionId]!.isConnected || !sessionMap[connectionId]!.isAuthorized {
            reject("not_connected", "The connection with this uuid \(connectionId) is not connected", nil);
            return;
        }
        if channelMap[connectionId]?[channelId] == nil {
            reject("no_channel_with_this_id", "There is no channel with the id \(channelId)", nil);
            return;
        }
        channelMap[connectionId]![channelId]!.close();
        channelMap[connectionId]![channelId] = nil;
        resolve(nil);
    }
    
    @objc
    override static func requiresMainQueueSetup() -> Bool{
        return false;
    }
    
    override func supportedEvents() -> [String]! {
        return [NATIVE_EVENTS.resolve, NATIVE_EVENTS.reject].map({ $0.rawValue })
    }
    
    override func stopObserving() {
        hasListeners = false;
    }
    
    override func startObserving() {
        hasListeners = true;
    }
    
}
