/**
 * Server Entrypoint
 * Initializes database connection, seeds initial catalog if needed, and starts HTTP listener.
 */

import http from 'http';
import { WebSocketServer } from 'ws';
import { createApp } from './app.js';
import { connectDB, disconnectDB } from './config/database.js';
import { env } from './config/env.js';
import { ModelCatalog } from './models/ModelCatalog.js';
import { MODEL_MODES } from './config/constants.js';
import { authenticateWebSocket, handleRecommendationWS } from './websocket/recommendation.ws.js';
import { handleGpuMarketWS } from './websocket/gpuMarket.ws.js';
import { handleInstanceStatusWS } from './websocket/instanceStatus.ws.js';
import { instancePollerService } from './services/instancePoller.service.js';

// Default AI model registry to seed on initial database setup
const INITIAL_MODELS = [
  {
    modelId: 'qwen-image-2.1',
    displayName: 'Qwen-Image 2.1',
    mode: MODEL_MODES.IMAGE,
    hfRepoId: 'Qwen/Qwen-Image-2.1',
    sizeGB: 15,
    requiredVramGB: 16,
    defaultSteps: 40,
    defaultGuidance: 1.0,
  },
  {
    modelId: 'flux-kontext-dev',
    displayName: 'FLUX.1 Kontext [dev]',
    mode: MODEL_MODES.IMAGE,
    hfRepoId: 'black-forest-labs/FLUX.1-Kontext-dev',
    sizeGB: 24,
    requiredVramGB: 24,
    defaultSteps: 16,
    defaultGuidance: 3.5,
  },
  {
    modelId: 'sdxl-base-1.0',
    displayName: 'SDXL Base 1.0',
    mode: MODEL_MODES.IMAGE,
    hfRepoId: 'stabilityai/stable-diffusion-xl-base-1.0',
    sizeGB: 6.9,
    requiredVramGB: 12,
    defaultSteps: 30,
    defaultGuidance: 7.0,
  },
  {
    modelId: 'z-image-turbo',
    displayName: 'Z-Image Turbo',
    mode: MODEL_MODES.IMAGE,
    hfRepoId: 'Tongyi-MAI/Z-Image-Turbo',
    sizeGB: 6.2,
    requiredVramGB: 12,
    defaultSteps: 9,
    defaultGuidance: 0.0,
  },
  {
    modelId: 'wan-2.1-t2v-1.3b',
    displayName: 'Wan 2.1 T2V 1.3B',
    mode: MODEL_MODES.VIDEO,
    hfRepoId: 'Wan-AI/Wan2.1-T2V-1.3B-Diffusers',
    sizeGB: 3.5,
    requiredVramGB: 12,
    defaultSteps: 30,
    defaultGuidance: 5.0,
  },
  {
    modelId: 'wan-2.1-i2v-14b',
    displayName: 'Wan 2.1 I2V 14B',
    mode: MODEL_MODES.VIDEO,
    hfRepoId: 'Wan-AI/Wan2.1-I2V-14B-480P-Diffusers',
    sizeGB: 28,
    requiredVramGB: 24,
    defaultSteps: 30,
    defaultGuidance: 5.0,
  },
  {
    modelId: 'wan-2.2-animate-14b',
    displayName: 'Wan 2.2 Animate 14B',
    mode: MODEL_MODES.MOTION,
    hfRepoId: 'Wan-AI/Wan2.2-Animate-14B',
    sizeGB: 28,
    requiredVramGB: 24,
    defaultSteps: 4,
    defaultGuidance: 1.0,
  },
  {
    modelId: 'minimax-h3',
    displayName: 'MiniMax-H3 Video+Audio',
    mode: MODEL_MODES.MOTION,
    hfRepoId: 'MiniMaxAI/MiniMax-H3',
    sizeGB: 33,
    requiredVramGB: 32,
    defaultSteps: 30,
    defaultGuidance: 6.0,
  },
  {
    modelId: 'chatterbox-tts',
    displayName: 'Chatterbox TTS',
    mode: MODEL_MODES.VOICE,
    hfRepoId: 'ResembleAI/chatterbox',
    sizeGB: 1.2,
    requiredVramGB: 4,
    defaultSteps: 1,
    defaultGuidance: 0.5,
  },
  {
    modelId: 'breeze-tts-2',
    displayName: 'Breeze TTS 2',
    mode: MODEL_MODES.VOICE,
    hfRepoId: 'BreezeBlue/Breeze-TTS-2',
    sizeGB: 6.8,
    requiredVramGB: 8,
    defaultSteps: 1,
    defaultGuidance: 4.0,
  },
  {
    modelId: 'fashn-vton-1.5',
    displayName: 'FASHN VTON 1.5',
    mode: MODEL_MODES.VTON,
    hfRepoId: 'fashn-ai/fashn-vton-1.5',
    sizeGB: 2.1,
    requiredVramGB: 8,
    defaultSteps: 30,
    defaultGuidance: 1.5,
  },
  {
    modelId: 'realesrgan-x4plus',
    displayName: 'Real-ESRGAN x4plus',
    mode: MODEL_MODES.ENHANCER,
    hfRepoId: 'amd/realesrgan-x4plus',
    sizeGB: 0.15,
    requiredVramGB: 4,
    defaultSteps: 20,
    defaultGuidance: 1.0,
  },
];

async function seedModelCatalog() {
  try {
    for (const model of INITIAL_MODELS) {
      await ModelCatalog.findOneAndUpdate(
        { modelId: model.modelId },
        { $setOnInsert: model },
        { upsert: true, new: true }
      );
    }
    console.info('[Catalog] Verified and seeded default AI model catalog.');
  } catch (error) {
    console.warn(`[Catalog] Non-fatal error seeding model catalog: ${error.message}`);
  }
}

async function startServer() {
  try {
    // 1. Connect to Database
    await connectDB();

    // 2. Seed Default Model Catalog
    await seedModelCatalog();

    // 3. Create Express App & HTTP Server
    const app = createApp();
    const server = http.createServer(app);

    // 4. Initialize WebSocket Servers (Multiplexed on HTTP server via upgrade)
    const wssRecommendations = new WebSocketServer({ noServer: true });
    const wssGpuMarket = new WebSocketServer({ noServer: true });
    const wssInstanceStatus = new WebSocketServer({ noServer: true });

    wssRecommendations.on('connection', async (ws, req) => {
      try {
        const user = await authenticateWebSocket(req);
        await handleRecommendationWS(ws, req, user);
      } catch (error) {
        ws.send(JSON.stringify({ type: 'ERROR', message: error.message }));
        ws.close(1008, error.message);
      }
    });

    wssGpuMarket.on('connection', async (ws, req) => {
      try {
        const user = await authenticateWebSocket(req);
        await handleGpuMarketWS(ws, req, user);
      } catch (error) {
        ws.send(JSON.stringify({ type: 'ERROR', message: error.message }));
        ws.close(1008, error.message);
      }
    });

    wssInstanceStatus.on('connection', async (ws, req) => {
      try {
        const user = await authenticateWebSocket(req);
        await handleInstanceStatusWS(ws, req, user);
      } catch (error) {
        ws.send(JSON.stringify({ type: 'ERROR', message: error.message }));
        ws.close(1008, error.message);
      }
    });

    server.on('upgrade', (request, socket, head) => {
      try {
        const { pathname } = new URL(request.url, `http://${request.headers.host || 'localhost'}`);

        if (pathname === '/ws/recommendations') {
          wssRecommendations.handleUpgrade(request, socket, head, (ws) => {
            wssRecommendations.emit('connection', ws, request);
          });
        } else if (pathname === '/ws/gpu-market') {
          wssGpuMarket.handleUpgrade(request, socket, head, (ws) => {
            wssGpuMarket.emit('connection', ws, request);
          });
        } else if (pathname === '/ws/instance-status') {
          wssInstanceStatus.handleUpgrade(request, socket, head, (ws) => {
            wssInstanceStatus.emit('connection', ws, request);
          });
        } else {
          socket.destroy();
        }
      } catch (err) {
        socket.destroy();
      }
    });

    // 5. Start Instance Poller Service
    instancePollerService.start();

    // 6. Start HTTP Listener
    server.listen(env.PORT, '0.0.0.0', () => {
      console.info('=====================================================');
      console.info(`🚀 AI Image Studio Cloud Orchestrator Started`);
      console.info(`📡 Port:        ${env.PORT}`);
      console.info(`🌍 Environment: ${env.NODE_ENV}`);
      console.info(`🩺 Health Check: http://localhost:${env.PORT}/api/v1/health`);
      console.info(`⚡ WS Recs:     ws://localhost:${env.PORT}/ws/recommendations`);
      console.info(`⚡ WS Market:   ws://localhost:${env.PORT}/ws/gpu-market`);
      console.info(`⚡ WS Status:   ws://localhost:${env.PORT}/ws/instance-status`);
      console.info('=====================================================');
    });

    // 7. Graceful Termination Handlers
    const shutdown = async (signal) => {
      console.info(`\n[Server] Received ${signal}. Commencing graceful shutdown...`);
      instancePollerService.stop();
      wssRecommendations.close();
      wssGpuMarket.close();
      wssInstanceStatus.close(() => {
        console.info('[Server] WebSocket servers closed.');
      });
      server.close(async () => {
        console.info('[Server] HTTP connections closed.');
        await disconnectDB();
        process.exit(0);
      });

      // Force exit after 10 seconds if shutdown hangs
      setTimeout(() => {
        console.error('[Server] Forced shutdown after timeout.');
        process.exit(1);
      }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    process.on('unhandledRejection', (reason) => {
      console.error('[Fatal] Unhandled Promise Rejection:', reason);
    });

    process.on('uncaughtException', (error) => {
      console.error('[Fatal] Uncaught Exception:', error);
      process.exit(1);
    });
  } catch (error) {
    console.error(`[Fatal Startup Failure] ${error.message}`);
    process.exit(1);
  }
}

startServer();
