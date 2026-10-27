import os from 'node:os';

const callbacks = [];

function run() {
    callbacks.forEach(callback => callback());
}

process.on('exit', (code) => {
    run();
});

// `process.on(signal)` handlers receive the signal name, not an exit code.
['SIGINT', 'SIGTERM', 'SIGHUP'].forEach((signal) => {
    process.on(signal, () => {
        // Handle as a normal exit
        process.exit(128 + (os.constants.signals[signal] || 0));
    });
});

export function onExit(callback) {
    callbacks.push(callback);
}
