# @ridenui/react-native-riden-ssh

## Getting started

`$ npm install @ridenui/react-native-riden-ssh --save` or `$ yarn add @ridenui/react-native-riden-ssh`

### Pod

`$ cd ios && pod install && cd ..`

## Usage
```typescript
import { SSHClient, SSHConfig } from '@ridenui/react-native-riden-ssh';

const client = new SSHClient({
    host: "ssh host",
    username: "ssh user",
    password: "ssh password",
    port: 22,
} as SSHConfig);

const { stdout, stderr, code, signal } = await client.execute("uptime");

```
