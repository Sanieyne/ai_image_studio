#!/usr/bin/env node
/**
 * Marketing Campaign Dispatcher Script
 * Usage:
 *   node scripts/send_campaign.js --to=user@example.com --type=image
 *   node scripts/send_campaign.js --to=user@example.com --type=video
 *   node scripts/send_campaign.js --to=user@example.com --type=audio
 *   node scripts/send_campaign.js --to=user@example.com --type=digest
 *   node scripts/send_campaign.js --preview --type=digest
 */

import fs from 'fs';
import path from 'path';
import { emailService } from '../src/services/email.service.js';
import { marketingTemplates } from '../src/templates/marketing.template.js';

// Parse arguments
const args = process.argv.slice(2).reduce((acc, arg) => {
  const [k, v] = arg.replace(/^--/, '').split('=');
  acc[k] = v === undefined ? true : v;
  return acc;
}, {});

const toEmail = args.to || 'alhajine20@gmail.com';
const campaignType = args.type || 'digest';
const isPreviewOnly = Boolean(args.preview);

const sampleData = {
  image: {
    subject: 'Introducing Wan 2.1 & Flux Kontext on Cosmic-Gen AI',
    options: {
      subtitle: 'Experience state-of-the-art neural generation directly in your browser or desktop rig.',
      badge: '✦ NEW GENERATION ENGINE',
      bodyText: 'We have updated Cosmic-Gen Studio with ultra-fast inference and photorealistic rendering. Whether you are creating cinematic landscapes, hyper-realistic portraits, or concept art, our newest models deliver unrivaled detail and coherence.',
      imageUrl: 'https://cosmic-gen.com/media/preview-1.png',
      imageCaption: 'Rendered in 1.4 seconds with Cosmic-Gen Turbo Engine',
      featurePoints: [
        'Lightning-fast inference under 2 seconds with Turbo mode',
        'Full 4K upscaling and negative prompt conditioning',
        'Available in both Cloud GPU and Unlimited Local Desktop Mode',
      ],
      ctaText: 'Launch Studio & Try Now',
      ctaUrl: 'https://cosmic-gen.com',
    },
  },
  video: {
    subject: '🎬 New: AI Video Generation is Now Live on Cosmic-Gen',
    options: {
      subtitle: 'Transform any text or still photo into high-definition 60fps cinematic video.',
      badge: 'NEURAL VIDEO ENGINE',
      videoThumbnailUrl: 'https://cosmic-gen.com/media/result_header.png',
      videoTitle: 'Minimax H3 Cinematic Motion Demo',
      videoDuration: '0:45',
      bodyText: 'Create stunning camera pans, fluid character animation, and dynamic lighting effects from a single prompt. Our new video orchestration engine brings motion to your imagination without complex timeline software.',
      featurePoints: [
        'High frame rate neural motion with temporal consistency',
        'Seamless integration with your saved gallery generations',
        'Zero render queues on dedicated cloud instances',
      ],
      ctaText: 'Watch Demo & Generate Video',
      ctaUrl: 'https://cosmic-gen.com/gallery',
    },
  },
  audio: {
    subject: '🎙️ Announcing Chatterbox Voice Studio — Human-Grade AI Speech',
    options: {
      subtitle: 'Natural expressive speech synthesis, real-time voice cloning, and multilingual audio.',
      badge: 'VOICE & AUDIO AI',
      voiceModelName: 'Chatterbox Multilingual V2',
      sampleTitle: 'Neural Conversational Speech Sample',
      sampleDuration: '0:22',
      audioPreviewUrl: 'https://cosmic-gen.com/media/chatterbox_real_speech.wav',
      bodyText: 'Give your AI characters, games, and podcasts a lifelike voice. With support for over 15 languages, nuance inflection, and instant 3-second voice cloning, Chatterbox is now part of the Cosmic-Gen creative suite.',
      featurePoints: [
        'Studio-grade 24kHz clarity with emotion and pacing control',
        'Multilingual pronunciation: English, Spanish, French, Hausa, Hindi, and more',
        'Instant download in WAV and MP3 format for your projects',
      ],
      ctaText: 'Listen to Voice Samples',
      ctaUrl: 'https://cosmic-gen.com',
    },
  },
  digest: {
    subject: '✦ Cosmic-Gen Studio Update: Image, Video & Voice Capabilities',
    options: {
      subtitle: 'Everything new in the world of Cosmic-Gen creative tools this week.',
      introText: 'We have rolled out major updates across all three creative modalities in Cosmic-Gen AI. Explore what you can build today with our creative orchestrator.',
      imageSection: {
        title: 'Photorealistic Image Synthesis with Flux Kontext',
        description: 'Next-generation prompt adherence with ultra-fine textural precision and zero distortion.',
        imageUrl: 'https://cosmic-gen.com/media/preview-1.png',
      },
      videoSection: {
        title: 'Cinematic Motion Engine',
        description: 'Bring any image to life with neural fluid camera dynamics and character motion.',
        thumbnailUrl: 'https://cosmic-gen.com/media/result_header.png',
        videoUrl: 'https://cosmic-gen.com/gallery',
      },
      audioSection: {
        title: 'Chatterbox Neural Voice Cloning',
        description: 'Generate lifelike human voiceover and speech synthesis from prompt text in seconds.',
        audioUrl: 'https://cosmic-gen.com/media/chatterbox_real_speech.wav',
        duration: '0:24',
      },
      ctaText: 'Explore All New Features',
      ctaUrl: 'https://cosmic-gen.com',
    },
  },
};

const campaign = sampleData[campaignType] || sampleData.digest;

async function run() {
  if (isPreviewOnly) {
    let html = '';
    if (campaignType === 'video') {
      html = marketingTemplates.createVideoCampaign({ headline: campaign.subject, ...campaign.options });
    } else if (campaignType === 'audio') {
      html = marketingTemplates.createAudioCampaign({ headline: campaign.subject, ...campaign.options });
    } else if (campaignType === 'digest') {
      html = marketingTemplates.createMultiMediaDigest({ headline: campaign.subject, ...campaign.options });
    } else {
      html = marketingTemplates.createImageCampaign({ headline: campaign.subject, ...campaign.options });
    }

    const outPath = `/tmp/preview_${campaignType}.html`;
    fs.writeFileSync(outPath, html, 'utf8');
    console.log(`[Preview] Generated preview HTML at: ${outPath} (${html.length} bytes)`);
    return;
  }

  console.log(`[Campaign] Sending ${campaignType} campaign to: ${toEmail}...`);
  console.log(`[Campaign] Subject: ${campaign.subject}`);
  console.log(`[Campaign] Sender: Cosmic-Gen <marketing@cosmic-gen.com>`);

  try {
    const result = await emailService.sendMarketingCampaign({
      to: toEmail,
      from: 'Cosmic-Gen <marketing@cosmic-gen.com>',
      subject: campaign.subject,
      type: campaignType,
      options: campaign.options,
    });
    console.log('[Campaign] Success! Dispatch result:', result);
  } catch (err) {
    console.error('[Campaign] Error dispatching email:', err);
    process.exit(1);
  }
}

run();
