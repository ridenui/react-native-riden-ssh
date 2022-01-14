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
    
    override init() {
        super.init();
        print("+ openConsolePipe()");
        self.openConsolePipe();
        print("- openConsolePipe()");
    }

    @objc(connect:port:username:password:resolver:rejecter:)
    func connect(_ host: String, port: NSNumber, username: String, password: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let id = UUID().uuidString;
        do {
            let folderURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let knownHostFile = folderURL.appendingPathComponent("known_hosts")
            let idLocation = folderURL.appendingPathComponent("id_rsa")
            
            let keyPair = try generateRSAKeyPair();
            
            if !FileManager.default.fileExists(atPath: idLocation.path) {
                try keyPair.privateKey.write(toFile: idLocation.path, atomically: true, encoding: .utf8);
            }
            let options = SSHOption(host: host, port: port.intValue, username: username, password: password, knownHostFile: knownHostFile.path, idRsaLocation: idLocation.path);
            sessionMap[id] = SSH(options: options)
            resolve(id);
        } catch {
            reject("ssh-init-failed", error.localizedDescription, error);
        }
        
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
                        "signal": result.exitSignal as Any,
                        "stdout": result.stdout.split(whereSeparator: \.isNewline),
                        "stderr": result.stderr.split(whereSeparator: \.isNewline),
                    ])
                } catch {
                    print(error)
                    reject("ssh_command_exec_error", error.localizedDescription, error);
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
                    print(error)
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
            
            Task.detached {
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
                    print(error)
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
        Task.detached {
            try await self.sessionMap[connectionId]!.cancel(id: channelId);
        }
        print("Received cancel request for channel \(channelId) on \(connectionId)");
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
    
    var inputPipe: Pipe?;
    
    var outputPipe: Pipe?;

    func openConsolePipe() {
        //open a new Pipe to consume the messages on STDOUT and STDERR
        inputPipe = Pipe()

        //open another Pipe to output messages back to STDOUT
        outputPipe = Pipe()
                
        guard let inputPipe = inputPipe, let outputPipe = outputPipe else {
            return
        }
                
        let pipeReadHandle = inputPipe.fileHandleForReading

        //from documentation
        //dup2() makes newfd (new file descriptor) be the copy of oldfd (old file descriptor), closing newfd first if necessary.
                
        //here we are copying the STDOUT file descriptor into our output pipe's file descriptor
        //this is so we can write the strings back to STDOUT, so it can show up on the xcode console
        dup2(STDOUT_FILENO, outputPipe.fileHandleForWriting.fileDescriptor)
                
        //In this case, the newFileDescriptor is the pipe's file descriptor and the old file descriptor is STDOUT_FILENO and STDERR_FILENO
                        
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        //listen in to the readHandle notification
        NotificationCenter.default.addObserver(self, selector: #selector(self.handlePipeNotification), name: FileHandle.readCompletionNotification, object: pipeReadHandle)

        //state that you want to be notified of any data coming across the pipe
        pipeReadHandle.readInBackgroundAndNotify()
    }
    
    @objc func handlePipeNotification(notification: Notification) {
        //note you have to continuously call this when you get a message
        //see this from documentation:
        //Note that this method does not cause a continuous stream of notifications to be sent. If you wish to keep getting notified, you’ll also need to call readInBackgroundAndNotify() in your observer method.
        inputPipe?.fileHandleForReading.readInBackgroundAndNotify()

        if let userInfo = notification.userInfo, let data = userInfo[NSFileHandleNotificationDataItem] as? Data,
            let str = String(data: data, encoding: String.Encoding.ascii) {
                        
            //write the data back into the output pipe. the output pipe's write file descriptor points to STDOUT. this allows the logs to show up on the xcode console
            outputPipe?.fileHandleForWriting.write(data)

            // `str` here is the log/contents of the print statement
            //if you would like to route your print statements to the UI: make
            //sure to subscribe to this notification in your VC and update the UITextView.
            //Or if you wanted to send your print statements to the server, then
            //you could do this in your notification handler in the app delegate.
            
            guard let logFile = ReactNativeRidenSsh.logFile else {
                return
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            
            guard let logData = (timestamp + ": " + str + "\n").data(using: String.Encoding.utf8) else { return }
            
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logData)
                    fileHandle.closeFile()
                }
            } else {
                try? logData.write(to: logFile, options: .atomicWrite)
            }
        }
    }
    
    static var logFile: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        let dateString = formatter.string(from: Date())
        let fileName = "\(dateString).log"
        return documentsDirectory.appendingPathComponent(fileName)
    }
}
