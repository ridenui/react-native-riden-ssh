//
//  ReactNativeRidenSsh.swift
//  react-native-riden-ssh
//
//  Created by Nils Bergmann on 30/11/2021.
//

import Foundation
import SwifterSwiftSSH

enum NATIVE_EVENTS: String {
    case resolve = "react-native-riden-ssh-resolve"
    case reject = "react-native-riden-ssh-reject"
    case onStdout = "react-native-riden-ssh-on-stdout"
    case onStderr = "react-native-riden-ssh-on-stderr"
    case onCancelId = "react-native-riden-ssh-cancel-id";
}


@objc(ReactNativeRidenSsh)
class ReactNativeRidenSsh: RCTEventEmitter {

    var hasListeners: Bool = false;

    private var sessionMap: Dictionary<String, SSH> = [:];

    let cancelLock = NSLock();

    @objc(connect:port:username:password:resolver:rejecter:)
    func connect(_ host: String, port: NSNumber, username: String, password: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let id = UUID().uuidString;
        let options = SSHOption(host: host, port: port.intValue, username: username, password: password);
        sessionMap[id] = SSH(options: options)
        resolve(id);
    }

    @objc(disconnect:resolver:rejecter:)
    func disconnect(_ connectionId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        if sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No SSH with the uuid \(connectionId)", nil);
            return;
        }
        Task {
            await sessionMap[connectionId]!.disconnect();
        }
        resolve(nil);
    }

    @objc(executeCommand:command:resolver:rejecter:)
    func executeCommand(_ connectionId: String, command: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        if self.sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No SSH with the uuid \(connectionId)", nil);
            return;
        }
        DispatchQueue.init(label: "ssh-\(connectionId)-main").async {
            Task {
                do {
                    let result = try await self.sessionMap[connectionId]!.exec(command: command);
                    
                    resolve([
                        "code": result.exitCode,
                        "signal": result.exitSignal,
                        "stdout": result.stdout.split(whereSeparator: \.isNewline),
                        "stderr": result.stderr.split(whereSeparator: \.isNewline),
                    ])
                } catch {
                    reject(error);
                }
            }
        }
    }

    @objc(executeStreamCommand:command:eventCallback:)
    func executeStreamCommand(_ connectionId: String, command: String, eventCallback: RCTResponseSenderBlock) {
        let channelId = UUID().uuidString;
        let functionId = UUID().uuidString;
        
        eventCallback([functionId]);

        let eventSendCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            if self.hasListeners {
                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
            }
        }

        let resolverCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            if self.hasListeners {
                eventSendCallback(eventName, argArray);
            }
        };

        if self.sessionMap[connectionId] == nil {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "no_connection_with_this_id", "message": "No SSH with the uuid \(connectionId)"]
            ]);
            return;
        }

        DispatchQueue.init(label: "ssh-\(connectionId)-\(channelId)").async {
            
            Task {
                let delegate = SSHExecEventHandler { stdout in
                    eventSendCallback(.onStdout, [stdout]);
                } onStderr: { stderr in
                    eventSendCallback(.onStderr, [stderr]);
                } cancelFunction: { id in
                    eventSendCallback(.onCancelId, [id]);
                }
                    
                do {
                    let result = try await self.sessionMap[connectionId]!.exec(command: command, delegate: delegate)
                    
                    resolverCallback(NATIVE_EVENTS.resolve, [
                        [
                            "code": result.exitCode,
                            "signal": result.exitSignal as Any,
                        ]
                    ])
                } catch {
                    resolverCallback(NATIVE_EVENTS.reject, [
                        [
                            "id": "ssh_error",
                            "message": error.localizedDescription
                        ]
                    ]);
                }
            }
        }
    }

    @objc(executeCommandCancelable:command:eventCallback:)
    func executeCommandCancelable(_ connectionId: String, command: String, eventCallback: RCTResponseSenderBlock) {
        let channelId = UUID().uuidString;
        let functionId = UUID().uuidString;
        
        eventCallback([functionId]);

        let eventSendCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            if self.hasListeners {
                self.sendEvent(withName: eventName.rawValue, body: [functionId, argArray as Any])
            }
        }

        let resolverCallback = { (eventName: NATIVE_EVENTS, argArray: [Any]?) in
            if self.hasListeners {
                eventSendCallback(eventName, argArray);
            }
        };

        if self.sessionMap[connectionId] == nil {
            resolverCallback(NATIVE_EVENTS.reject, [
                ["id": "no_connection_with_this_id", "message": "No SSH with the uuid \(connectionId)"]
            ]);
            return;
        }

        DispatchQueue.init(label: "ssh-\(connectionId)-\(channelId)").async {
            
            Task {
                let delegate = SSHExecEventHandler(onStdout: nil, onStderr: nil) { cancelId in
                    eventSendCallback(.onCancelId, [cancelId]);
                }
                    
                do {
                    let result = try await self.sessionMap[connectionId]!.exec(command: command, delegate: delegate)
                    
                    resolverCallback(NATIVE_EVENTS.resolve, [
                        [
                            "code": result.exitCode,
                            "signal": result.exitSignal as Any,
                            "stdout": result.stdout.split(whereSeparator: \.isNewline),
                            "stderr": result.stderr.split(whereSeparator: \.isNewline),
                        ]
                    ])
                } catch {
                    resolverCallback(NATIVE_EVENTS.reject, [
                        [
                            "id": "ssh_error",
                            "message": error.localizedDescription
                        ]
                    ]);
                }
            }
        }
    }

    @objc(cancelCommand:channelId:resolver:rejecter:)
    func cancelCommand(_ connectionId: String, channelId: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        print("Received cancel request for channel \(channelId) on \(connectionId)");
        if self.sessionMap[connectionId] == nil {
            reject("no_connection_with_this_id", "No SSH with the uuid \(connectionId)", nil);
            self.cancelLock.unlock();
            return;
        }
        Task {
            try await self.sessionMap[connectionId]!.cancel(id: channelId);
        }
        resolve(nil);
    }

    @objc
    override static func requiresMainQueueSetup() -> Bool{
        return false;
    }

    override func supportedEvents() -> [String]! {
        return [NATIVE_EVENTS.resolve, NATIVE_EVENTS.reject, NATIVE_EVENTS.onStderr, NATIVE_EVENTS.onStdout, NATIVE_EVENTS.onCancelId].map({ $0.rawValue })
    }

    override func stopObserving() {
        hasListeners = false;
    }

    override func startObserving() {
        hasListeners = true;
    }

}
