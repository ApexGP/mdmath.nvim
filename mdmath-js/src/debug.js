// Utitiy functions for debugging
import { exec } from 'node:child_process';
import fs from 'fs';

export async function saveFile(filename, data) {
    return new Promise((resolve, reject) => {
        fs.writeFile(filename, data, (err) => {
            if (err) {
                reject(err);
            } else {
                resolve();
            }
        });
    });
}

export function sendNotification(message) {
    if (process.platform !== 'linux')
        return;

    exec(`notify-send "Processor.js" '${message}'`, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error: ${error.message}`);
        }
        if (stderr) {
            console.error(`Stderr: ${stderr}`);
        }
    });
}
