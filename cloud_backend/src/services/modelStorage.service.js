/**
 * Model Weights Storage Service (Cloudflare R2 via S3 API)
 * Uploads model weight files, mints signed download URLs for Vast.ai
 * instances pulling on-demand, and lists stored model files.
 *
 * Key layout: models/{modelId}/{filename} (filename may contain repo
 * subpaths, e.g. "transformer/diffusion_pytorch_model.safetensors").
 */

import fs from 'fs';
import path from 'path';
import { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command, HeadObjectCommand } from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../config/env.js';

// Single-shot PutObject caps at 5GB; weight shards can exceed that, so all
// uploads go through managed multipart regardless of size.
const MULTIPART_THRESHOLD_BYTES = 100 * 1024 * 1024; // 100MB parts
const MULTIPART_QUEUE_SIZE = 4;

class ModelStorageService {
  constructor() {
    this._client = null;
  }

  get bucket() {
    return env.R2_BUCKET_NAME;
  }

  get isConfigured() {
    return Boolean(
      env.R2_ENDPOINT &&
      env.R2_ACCESS_KEY_ID &&
      env.R2_SECRET_ACCESS_KEY &&
      env.R2_BUCKET_NAME
    );
  }

  _assertConfigured() {
    if (!this.isConfigured) {
      throw new Error(
        '[ModelStorage] R2 is not configured. Set R2_ENDPOINT, R2_ACCESS_KEY_ID, ' +
        'R2_SECRET_ACCESS_KEY and R2_BUCKET_NAME in .env (see .env.example).'
      );
    }
  }

  _clientInstance() {
    this._assertConfigured();
    if (!this._client) {
      this._client = new S3Client({
        region: 'auto',
        endpoint: env.R2_ENDPOINT,
        credentials: {
          accessKeyId: env.R2_ACCESS_KEY_ID,
          secretAccessKey: env.R2_SECRET_ACCESS_KEY,
        },
      });
    }
    return this._client;
  }

  /**
   * Builds the R2 object key for a model file.
   * @param {string} modelId - Catalog model id (e.g. 'flux-kontext-dev')
   * @param {string} filename - Repo-relative path (e.g. 'transformer/model.safetensors')
   * @returns {string} - e.g. 'models/flux-kontext-dev/transformer/model.safetensors'
   */
  keyFor(modelId, filename) {
    const cleanId = String(modelId || '').trim().replace(/^\/+|\/+$/g, '');
    const cleanFile = String(filename || '').replace(/^\/+/, '');
    if (!cleanId || !cleanFile || cleanFile.includes('..')) {
      throw new Error(`[ModelStorage] Invalid modelId/filename: '${modelId}' / '${filename}'`);
    }
    return `models/${cleanId}/${cleanFile}`;
  }

  /**
   * Uploads a local weight file to R2 (managed multipart, any size).
   * @param {string} localPath - Absolute path to the local file
   * @param {string} modelId - Catalog model id
   * @param {string} filename - Repo-relative destination path
   * @returns {Promise<{ key: string, size: number, etag: string }>}
   */
  async uploadModel(localPath, modelId, filename) {
    this._assertConfigured();
    const key = this.keyFor(modelId, filename);
    const absolutePath = path.resolve(localPath);
    const stat = await fs.promises.stat(absolutePath).catch(() => null);
    if (!stat || !stat.isFile()) {
      throw new Error(`[ModelStorage] Local file not found: ${absolutePath}`);
    }

    const upload = new Upload({
      client: this._clientInstance(),
      params: {
        Bucket: this.bucket,
        Key: key,
        Body: fs.createReadStream(absolutePath),
        ContentLength: stat.size,
      },
      partSize: MULTIPART_THRESHOLD_BYTES,
      queueSize: MULTIPART_QUEUE_SIZE,
      leavePartsOnError: false,
    });

    const result = await upload.done();
    return {
      key,
      size: stat.size,
      etag: (result.ETag || '').replace(/"/g, ''),
    };
  }

  /**
   * Mints a signed HTTPS download URL for a stored weight file.
   * The bucket stays private; Vast.ai instances pull via these URLs.
   * (S3 pre-signed expiry is enforced when the download STARTS, so even
   * multi-GB pulls only need an expiry covering provisioning delay.)
   * @param {string} modelId - Catalog model id
   * @param {string} filename - Repo-relative path
   * @param {number} [expiresInSec=3600] - URL validity window
   * @returns {Promise<string>} - Signed download URL
   */
  async getModelDownloadUrl(modelId, filename, expiresInSec = 3600) {
    this._assertConfigured();
    const key = this.keyFor(modelId, filename);
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    return getSignedUrl(this._clientInstance(), command, { expiresIn: expiresInSec });
  }

  /**
   * Lists all stored files for a model (paginated internally).
   * @param {string} modelId - Catalog model id
   * @returns {Promise<Array<{ key: string, filename: string, size: number, lastModified: Date, etag: string }>>}
   */
  async listModelFiles(modelId) {
    this._assertConfigured();
    const prefix = `models/${String(modelId).trim().replace(/^\/+|\/+$/g, '')}/`;
    const client = this._clientInstance();
    const files = [];
    let continuationToken;
    do {
      const res = await client.send(new ListObjectsV2Command({
        Bucket: this.bucket,
        Prefix: prefix,
        ContinuationToken: continuationToken,
        MaxKeys: 1000,
      }));
      for (const obj of res.Contents || []) {
        files.push({
          key: obj.Key,
          filename: obj.Key.slice(prefix.length),
          size: obj.Size || 0,
          lastModified: obj.LastModified,
          etag: (obj.ETag || '').replace(/"/g, ''),
        });
      }
      continuationToken = res.IsTruncated ? res.NextContinuationToken : undefined;
    } while (continuationToken);
    return files;
  }

  /**
   * Stats a single stored file (size + etag) without downloading it.
   * @returns {Promise<{ size: number, etag: string } | null>} - null when missing
   */
  async statModelFile(modelId, filename) {
    this._assertConfigured();
    try {
      const res = await this._clientInstance().send(new HeadObjectCommand({
        Bucket: this.bucket,
        Key: this.keyFor(modelId, filename),
      }));
      return {
        size: res.ContentLength || 0,
        etag: (res.ETag || '').replace(/"/g, ''),
      };
    } catch (err) {
      if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) return null;
      throw err;
    }
  }
}

export const modelStorageService = new ModelStorageService();
