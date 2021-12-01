//
//  ReactNativeRidenSsh.swift
//  react-native-riden-ssh
//
//  Created by Nils Bergmann on 30/11/2021.
//

import Foundation
import NMSSH_riden

@objc(ReactNativeRidenSsh)
class ReactNativeRidenSsh: NSObject {
    
    private var sessionMap: Dictionary<String, NMSSHSession> = [:];
    
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
        let stdout = sessionMap[connectionId]!.channel.execute(command, error: &error);
        if error != nil {
            let exitCodeString: String = error?.userInfo["exit_code"] as? String ?? "1";
            let exitCode = Int(exitCodeString) ?? 1;
            
            resolve([
                "code": exitCode,
                "signal": 1,
                "stdout": [],
                "stderr": error!.localizedDescription.split(separator: "\n"),
            ])
            return;
        }
        resolve([
            "code": 0,
            "signal": 0,
            "stdout": stdout.split(separator: "\n"),
            "stderr": []
        ])
    }
    
    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }
    
}
