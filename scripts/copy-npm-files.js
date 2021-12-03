#!/usr/bin/env node
const { execSync } = require("child_process");
const { join, dirname } = require("path");
const { existsSync, writeFileSync } = require("fs");

const resultString = execSync("npm publish --dry-run --json", {
    cwd: join(__dirname, "../"),
}).toString();

const resultJson = JSON.parse(resultString);

if (existsSync(join(__dirname, "../package/"))) {
    execSync(`rm -r ${join(__dirname, "../package/")}`);
}

execSync("mkdir package", {
    cwd: join(__dirname, "../"),
});

for (const { path } of resultJson.files) {
    execSync(`mkdir -p ./package/${dirname(path)}`, {
        cwd: join(__dirname, "../"),
    });
    execSync(`cp ${path} ./package/${path}`, {
        cwd: join(__dirname, "../"),
    });
}

const newPackageJson = require("../package/package.json");

newPackageJson.name = "@ridenui/react-native-riden-ssh-test";

writeFileSync(
    join(__dirname, "../package/package.json"),
    JSON.stringify(newPackageJson)
);
