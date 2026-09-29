/**
 * Moderation Service
 * Automated safety filtering integrating Google Cloud Vision SafeSearch API
 * for images and representative video frame extraction.
 */

import vision from '@google-cloud/vision';
import { execFile } from 'child_process';
import util from 'util';
import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import os from 'os';

const execFileAsync = util.promisify(execFile);

class ModerationService {
  constructor() {
    this.provider = 'google-vision';
    this.client = null;
    this.mockHandler = null;
  }

  /**
   * Checks whether Google Cloud service account credentials are provided and accessible on disk.
   */
  hasCredentials() {
    const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.GOOGLE_CLOUD_KEYFILE;
    if (credPath) {
      try {
        return fsSync.existsSync(credPath);
      } catch {
        return false;
      }
    }
    return Boolean(process.env.GCP_SERVICE_ACCOUNT_KEY);
  }


  /**
   * For testing purposes: allows overriding provider logic to test block/review paths
   * without needing to generate or store prohibited content.
   */
  setMockHandler(fn) {
    this.mockHandler = fn;
  }

  /**
   * Resets mock handler back to live provider.
   */
  clearMockHandler() {
    this.mockHandler = null;
  }

  /**
   * Maps Google Vision SafeSearch likelihood categories to our safety verdicts:
   * - VERY_LIKELY on adult/violence/racy => 'block'
   * - LIKELY or POSSIBLE on adult/violence => 'review'
   * - Everything else => 'allow'
   */
  mapSafeSearchToVerdict(annotation) {
    const scores = {
      adult: annotation?.adult || 'UNKNOWN',
      violence: annotation?.violence || 'UNKNOWN',
      racy: annotation?.racy || 'UNKNOWN',
      medical: annotation?.medical || 'UNKNOWN',
      spoof: annotation?.spoof || 'UNKNOWN',
    };

    // Rule 1: Prohibited categories at VERY_LIKELY => block
    if (
      scores.adult === 'VERY_LIKELY' ||
      scores.violence === 'VERY_LIKELY' ||
      scores.racy === 'VERY_LIKELY'
    ) {
      return {
        verdict: 'block',
        scores,
        provider: this.provider,
        reason: 'Prohibited content detected (adult, violence, or racy rated VERY_LIKELY)',
      };
    }

    // Rule 2: Potential sensitive categories at LIKELY or POSSIBLE => review
    const reviewLikelihoods = ['LIKELY', 'POSSIBLE'];
    if (
      reviewLikelihoods.includes(scores.adult) ||
      reviewLikelihoods.includes(scores.violence)
    ) {
      return {
        verdict: 'review',
        scores,
        provider: this.provider,
        reason: 'Sensitive content detected (adult or violence rated POSSIBLE or LIKELY)',
      };
    }

    // Rule 3: Safe categories => allow
    return {
      verdict: 'allow',
      scores,
      provider: this.provider,
      reason: 'Content cleared automated safety checks',
    };
  }

  /**
   * Check image safety buffer using Google Cloud Vision SafeSearch.
   * If any error occurs (network failure, missing credentials, quota exceeded),
   * fails safely to 'review' — never 'allow'.
   *
   * @param {Buffer} imageBuffer - Raw image file buffer
   * @returns {Promise<{ verdict: 'allow' | 'review' | 'block', scores: Object, provider: string, reason?: string }>}
   */
  async checkImageSafety(imageBuffer) {
    if (!imageBuffer || !Buffer.isBuffer(imageBuffer) || imageBuffer.length === 0) {
      return {
        verdict: 'review',
        scores: { error: 'Empty or invalid image buffer' },
        provider: this.provider,
        reason: 'Invalid media buffer, held for manual review',
      };
    }

    // Check if test mock handler is active
    if (typeof this.mockHandler === 'function') {
      try {
        const mockResult = await this.mockHandler(imageBuffer);
        if (mockResult) return mockResult;
      } catch (mockErr) {
        return {
          verdict: 'review',
          scores: { error: mockErr.message },
          provider: 'mock',
          reason: 'Mock moderation failure, defaulting to review',
        };
      }
    }

    if (!this.hasCredentials()) {
      return {
        verdict: 'review',
        scores: { error: 'Google Cloud service account credentials not configured in environment' },
        provider: this.provider,
        reason: 'Automated moderation credentials pending GCP setup; held for manual review',
      };
    }

    try {
      if (!this.client) {
        const clientOptions = {};
        if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
          clientOptions.keyFilename = process.env.GOOGLE_APPLICATION_CREDENTIALS;
        }
        this.client = new vision.ImageAnnotatorClient(clientOptions);
      }


      const [result] = await this.client.safeSearchDetection({
        image: { content: imageBuffer },
      });

      const detections = result?.safeSearchAnnotation;
      if (!detections) {
        throw new Error('Google Cloud Vision returned empty SafeSearch annotations');
      }

      return this.mapSafeSearchToVerdict(detections);
    } catch (err) {
      console.error('[ModerationService] Google Vision SafeSearch check failed:', err.message);
      // FAIL-SAFE: Any failure must default to 'review', NEVER 'allow'
      return {
        verdict: 'review',
        scores: { error: err.message },
        provider: this.provider,
        reason: `Automated safety check error (${err.message}). Defaulting to manual review.`,
      };
    }
  }

  /**
   * Check video safety by extracting representative frames with ffmpeg
   * and running SafeSearch on each frame.
   *
   * @param {string} videoFilePath - Absolute path to local video file
   * @returns {Promise<{ verdict: 'allow' | 'review' | 'block', scores: Object, provider: string, reason?: string }>}
   */
  async checkVideoSafety(videoFilePath) {
    let tmpDir = null;
    try {
      tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mod-video-'));
      const outputPattern = path.join(tmpDir, 'frame_%02d.jpg');

      // Extract up to 3 representative frames using ffmpeg thumbnail filter
      await execFileAsync('ffmpeg', [
        '-y',
        '-i',
        videoFilePath,
        '-vf',
        'thumbnail,scale=512:-1',
        '-frames:v',
        '3',
        outputPattern,
      ]);

      const files = await fs.readdir(tmpDir);
      const frameFiles = files.filter((f) => f.startsWith('frame_')).sort();

      if (frameFiles.length === 0) {
        return {
          verdict: 'review',
          scores: { error: 'No video frames could be extracted for analysis' },
          provider: this.provider,
          reason: 'Video frames could not be extracted; held for manual review',
        };
      }

      const frameResults = [];
      for (const frameFile of frameFiles) {
        const frameBuffer = await fs.readFile(path.join(tmpDir, frameFile));
        const frameResult = await this.checkImageSafety(frameBuffer);
        frameResults.push(frameResult);

        // Fail early if any frame is blocked
        if (frameResult.verdict === 'block') {
          return {
            verdict: 'block',
            scores: { frameTrigger: frameResult.scores },
            provider: this.provider,
            reason: 'Video contains prohibited content in representative frames',
          };
        }
      }

      // If any frame triggered review, video triggers review
      const reviewFrame = frameResults.find((r) => r.verdict === 'review');
      if (reviewFrame) {
        return {
          verdict: 'review',
          scores: { frameTrigger: reviewFrame.scores },
          provider: this.provider,
          reason: 'Video contains sensitive content in representative frames',
        };
      }

      // All checked frames cleared
      return {
        verdict: 'allow',
        scores: { checkedFramesCount: frameResults.length },
        provider: this.provider,
        reason: 'All inspected video frames cleared safety checks',
      };
    } catch (err) {
      console.error('[ModerationService] Video moderation failed:', err.message);
      return {
        verdict: 'review',
        scores: { error: err.message },
        provider: this.provider,
        reason: 'Video processing error; held for manual review',
      };
    } finally {
      if (tmpDir) {
        try {
          await fs.rm(tmpDir, { recursive: true, force: true });
        } catch {
          // ignore cleanup errors
        }
      }
    }
  }

  /**
   * Unified media safety check.
   * Handles image, video, and audio according to policy.
   */
  async checkMediaSafety({ buffer, filePath, mediaType }) {
    if (mediaType === 'audio') {
      // Audio automated moderation is out of scope for this pass
      return {
        verdict: 'allow',
        scores: { automatedCheckSkipped: true },
        provider: 'system',
        reason: 'Audio generations bypass automated image checks (manual review queue available)',
      };
    }

    if (mediaType === 'video' && filePath) {
      return this.checkVideoSafety(filePath);
    }

    // Default to image safety check
    return this.checkImageSafety(buffer);
  }
}

export const moderationService = new ModerationService();
export default moderationService;
