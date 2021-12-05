//
//  StreamBridge.swift
//  ReactNativeRidenSsh
//
//  Created by Nils Bergmann on 04/12/2021.
//

import Foundation

typealias StreamBridgeCallback<T> = (T) -> Void;

@objc(StreamBridge)
class StreamBridge: NSObject, NMSSHChannelStreamReceiveDelegate {
    let onStdoutCallback: StreamBridgeCallback<String>;
    let onStderrCallback: StreamBridgeCallback<String>;
    let onExitCallback: StreamBridgeCallback<NSNumber>;
    let onErrorCallback: StreamBridgeCallback<Error>;
    
    init(onStdout: @escaping StreamBridgeCallback<String>, onStderr: @escaping StreamBridgeCallback<String>, onExit: @escaping StreamBridgeCallback<NSNumber>, onError: @escaping StreamBridgeCallback<Error>) {
        self.onStdoutCallback = onStdout;
        self.onStderrCallback = onStderr;
        self.onExitCallback = onExit;
        self.onErrorCallback = onError;
    }
    
    override init() {
        self.onStdoutCallback = { _ in };
        self.onStderrCallback = { _ in };
        self.onExitCallback = { _ in };
        self.onErrorCallback = { _ in };
    }
    
    @objc(onStdout:)
    func onStdout(_ stringText: String!) {
        self.onStdoutCallback(stringText);
    }
    
    @objc(onStderr:)
    func onStderr(_ stringText: String!) {
        self.onStderrCallback(stringText);
    }
    
    @objc(onExit:)
    func onExit(_ exitCode: NSNumber!) {
        self.onExitCallback(exitCode);
    }
    
    @objc(onError:)
    func onError(_ error: Error!) {
        self.onErrorCallback(error);
    }
}
