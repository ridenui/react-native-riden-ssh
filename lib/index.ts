import { NativeModules, NativeEventEmitter } from "react-native";
import AwaitLock from "./extended-await-lock";
import EventEmitter from "events";

const { SSH } = NativeModules;

export type SSHConfig = {
    host: string;
    port: number;
    username: string;
    password: string;
};

export type IExecuteResult = {
    stdout: string[];
    stderr: string[];
    code: number;
    signal?: unknown;
};

export type Newable<T> = { new (...args: any[]): T };

enum NATIVE_EVENTS {
    RESOLVE = "react-native-riden-ssh-resolve",
    REJECT = "react-native-riden-ssh-reject",
}

export class SSHClient extends EventEmitter {
    private config: SSHConfig;

    private connectionId?: string;

    private lock = new AwaitLock();

    private emitter: NativeEventEmitter;

    constructor(
        config: SSHConfig,
        nativeEventEmitterClass?: Newable<NativeEventEmitter>
    ) {
        super();
        this.config = config;
        this.emitter = nativeEventEmitterClass
            ? new nativeEventEmitterClass(SSH)
            : new NativeEventEmitter(SSH);

        this.emitter.addListener(NATIVE_EVENTS.RESOLVE, (...args) => {
            this.emit(NATIVE_EVENTS.RESOLVE, ...args);
        });
        this.emitter.addListener(NATIVE_EVENTS.REJECT, (...args) => {
            this.emit(NATIVE_EVENTS.REJECT, ...args);
        });
    }

    async connect() {
        await this.lock.acquireAsync();
        try {
            this.connectionId = await SSH.connect(
                this.config.host,
                this.config.port,
                this.config.username,
                this.config.password
            );
        } catch (e) {
            this.lock.release();
            return Promise.reject(e);
        }
        this.lock.release();
    }

    async disconnect() {
        await this.lock.acquireAsync();
        if (this.connectionId) {
            await SSH.disconnect(this.connectionId);
            this.connectionId = undefined;
        }
        this.lock.release();
    }

    execute<T extends boolean>(
        command: string,
        cancelable?: T
    ): Promise<
        T extends true
            ? [Promise<IExecuteResult>, () => void]
            : Promise<IExecuteResult>
    >;

    async execute(
        command: string,
        cancelable?: boolean
    ): Promise<
        [Promise<IExecuteResult>, () => void] | Promise<IExecuteResult>
    > {
        if (cancelable) {
            await this.lock.waitForRelease();
            if (!this.connectionId) {
                await this.connect();
            }
            let cancelFunction: () => Promise<void>;
            let functionId;
            await new Promise<void>((resolve) => {
                SSH.executeCommandCancelable(
                    this.connectionId,
                    command,
                    (functionIdNew, channelId) => {
                        cancelFunction = () => {
                            return SSH.cancelCommand(
                                this.connectionId,
                                channelId
                            ).catch(() => Promise.resolve());
                        };
                        functionId = functionIdNew;
                        resolve();
                    }
                );
            });
            return [
                new Promise((resolve, reject) => {
                    const [removeResolve] = this.addListenerWithRemove(
                        NATIVE_EVENTS.RESOLVE,
                        ([eventFunctionId, args]) => {
                            if (eventFunctionId === functionId) {
                                clearEvents();
                                resolve(args[0]);
                            }
                        }
                    );
                    const [removeReject] = this.addListenerWithRemove(
                        NATIVE_EVENTS.REJECT,
                        ([eventFunctionId, args]) => {
                            if (eventFunctionId === functionId) {
                                clearEvents();
                                reject(args[0]);
                            }
                        }
                    );

                    function clearEvents() {
                        removeResolve();
                        removeReject();
                    }
                }),
                // Required because typescript doesn't understand that we can't reach this part of the code without
                // the assignment of this function
                // @ts-ignore
                cancelFunction,
            ];
        } else {
            await this.lock.waitForRelease();
            if (!this.connectionId) {
                await this.connect();
            }
            return await SSH.executeCommand(this.connectionId, command);
        }
    }

    private addListenerWithRemove(
        eventName: string | symbol,
        listener: (...args: any[]) => void
    ) {
        this.addListener(eventName, listener);
        return [
            () => {
                this.removeListener(eventName, listener);
            },
        ];
    }

    async isConnected() {
        if (!this.connectionId) {
            return false;
        }
        return await SSH.isConnected(this.connectionId);
    }

    async test() {
        return;
    }
}
