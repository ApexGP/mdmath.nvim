import { createHash } from 'node:crypto';

/**
 * Computes the SHA-256 hash of the given data.
 * @param {string} data - The input data to be hashed.
 * @returns {string} The SHA-256 hash of the input data as a hexadecimal string.
 */
export function sha256Hash(data) {
    // A new hash per call, otherwise every digest would include the data from
    // all previous calls (the module-level instance is stateful).
    return createHash('sha256').update(data, 'utf8').digest('hex');
}
