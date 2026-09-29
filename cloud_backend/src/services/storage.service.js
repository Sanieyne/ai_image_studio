/**
 * Media Storage Service
 * Provides an abstract storage interface (currently backed by local disk,
 * swappable to Cloudflare R2 / S3 without modifying calling code).
 */

import fs from 'fs/promises';
import path from 'path';
import crypto from 'crypto';
import { env } from '../config/env.js';

class StorageService {
  constructor() {
    this.storagePath = env.MEDIA_STORAGE_PATH;
    this.publicBaseUrl = env.MEDIA_PUBLIC_URL;
  }

  /**
   * Constructs the public URL for a given relative storageKey.
   * @param {string} storageKey - Relative path (e.g. {userId}/{uuid}.png)
   * @returns {string} - Fully qualified public URL
   */
  getMediaUrl(storageKey) {
    if (!storageKey) return '';
    if (storageKey.startsWith('http://') || storageKey.startsWith('https://')) {
      return storageKey;
    }
    const cleanKey = storageKey.replace(/^\/+/, '');
    return `${this.publicBaseUrl}/${cleanKey}`;
  }

  /**
   * Uploads a media buffer to storage.
   * @param {Buffer} buffer - Raw media buffer
   * @param {Object} options
   * @param {string} options.userId - ID of the user uploading the media
   * @param {string} [options.mediaType] - 'image' | 'video' | 'audio'
   * @param {string} [options.extension] - File extension without or with dot (e.g. 'png', '.jpg')
   * @returns {Promise<{ storageKey: string, url: string }>}
   */
  async uploadMedia(buffer, { userId, mediaType = 'image', extension = 'png' }) {
    if (!buffer || !Buffer.isBuffer(buffer)) {
      throw new Error('Invalid buffer provided for media upload');
    }
    if (!userId) {
      throw new Error('userId is required for media upload');
    }

    // Sanitize extension
    let cleanExt = (extension || '').replace(/^\./, '').trim().toLowerCase();
    if (!cleanExt) {
      if (mediaType === 'video') cleanExt = 'mp4';
      else if (mediaType === 'audio') cleanExt = 'mp3';
      else cleanExt = 'png';
    }

    const uuid = crypto.randomUUID();
    const userFolder = String(userId);
    const fileName = `${uuid}.${cleanExt}`;
    const storageKey = `${userFolder}/${fileName}`;

    // Target directory on disk
    const targetDir = path.resolve(this.storagePath, userFolder);
    await fs.mkdir(targetDir, { recursive: true });

    // Target absolute file path
    const filePath = path.join(targetDir, fileName);

    // Verify path safety (prevent path traversal)
    if (!filePath.startsWith(path.resolve(this.storagePath))) {
      throw new Error('Security violation: invalid storage path destination');
    }

    await fs.writeFile(filePath, buffer);

    const url = this.getMediaUrl(storageKey);
    return { storageKey, url };
  }

  /**
   * Deletes media file from storage by its relative storageKey.
   * @param {string} storageKey - Relative path (e.g. {userId}/{uuid}.png)
   * @returns {Promise<boolean>} - True if deleted, false if file did not exist
   */
  async deleteMedia(storageKey) {
    if (!storageKey) return false;

    const baseDir = path.resolve(this.storagePath);
    const filePath = path.resolve(baseDir, storageKey);

    // Ensure filePath is strictly inside baseDir to prevent path traversal
    if (!filePath.startsWith(baseDir)) {
      throw new Error('Security violation: invalid storage key');
    }

    try {
      await fs.unlink(filePath);
      return true;
    } catch (err) {
      if (err.code === 'ENOENT') {
        return false;
      }
      throw err;
    }
  }
}

export const storageService = new StorageService();
export default storageService;
