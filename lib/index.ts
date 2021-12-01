import { NativeModules } from "react-native";
import AwaitLock from "./extended-await-lock";

const { ReactNativeRidenSsh } = NativeModules;

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

export class SSHClient {
    private config: SSHConfig;

    private connectionId?: string;

    private lock = new AwaitLock();

    constructor(config: SSHConfig) {
        this.config = config;
    }

    async connect() {
        await this.lock.acquireAsync();
        try {
            this.connectionId = await ReactNativeRidenSsh.connect(
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
            await ReactNativeRidenSsh.disconnect(this.connectionId);
            this.connectionId = undefined;
        }
        this.lock.release();
    }

    async execute(command: string): Promise<IExecuteResult> {
        await this.lock.waitForRelease();
        if (!this.connectionId) {
            await this.connect();
        }
        return await ReactNativeRidenSsh.executeCommand(
            this.connectionId,
            command
        );
    }

    async isConnected() {
        if (!this.connectionId) {
            return false;
        }
        return await ReactNativeRidenSsh.isConnected(this.connectionId);
    }

    async test() {
        return;
    }
}
