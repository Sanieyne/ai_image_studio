#!/usr/bin/env node
/**
 * Marketing Campaign Dispatcher Script
 * Usage:
 *   node scripts/send_campaign.js --to=user@example.com --type=digest
 *   node scripts/send_campaign.js --to=user@example.com --type=video
 *   node scripts/send_campaign.js --to=user@example.com --type=image
 *   node scripts/send_campaign.js --to=user@example.com --type=audio
 *   node scripts/send_campaign.js --preview --type=digest
 */

import fs from 'fs';
import path from 'path';
import { emailService } from '../src/services/email.service.js';
import { marketingTemplates } from '../src/templates/marketing.template.js';

const MEDIA_URL = 'https://cosmic-gen.com/media/marketing';
const BASE_URL = 'https://cosmic-gen.com';

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
    subject: 'Photorealism Redefined: Qwen Image 2.1 is Now Live on Cosmic-Gen',
    options: {
      headline: 'Photorealism Redefined: Qwen Image 2.1 is Live',
      subtitle: 'Flawless human anatomy, authentic Lagos street fashion, and sharp in-image typography.',
      badge: 'QWEN IMAGE 2.1 • PHOTOREALISM',
      bodyText: 'Our latest neural imaging pipeline is now operational on Cosmic-Gen. Powered by Qwen 2.1, experience photorealistic skin textures, accurate multi-subject lighting, and precise typography rendering for marketing posters and fashion editorials.',
      imageUrl: `${MEDIA_URL}/qwen_fashion_card.jpg`,
      imageAlt: 'Qwen 2.1 High Fashion Lagos Editorial',
      imageCaption: 'Rendered in 40 steps • Prompt: Full-body street style in vibrant Ankara print, Lagos',
      secondaryImageUrl: `${MEDIA_URL}/qwen_poster_card.jpg`,
      secondaryTitle: 'Sci-Fi Movie Poster Synthesis',
      featurePoints: [
        'Authentic African skin tones, high-fashion textiles, and realistic natural sunlight',
        'Flawless in-image typography for social ads, movie posters, and marketing banners',
        'Ultra-fine 4K upscaling with negative prompt controls and seed reproducibility',
      ],
      ctaText: 'Generate with Qwen 2.1 (Free)',
      ctaUrl: BASE_URL,
    },
  },
  video: {
    subject: 'Hollywood Motion: Minimax H3 4K Video Generation is Here',
    options: {
      headline: 'Minimax H3 Video Engine: Cinematic 4K AI Video is Here',
      subtitle: 'Render fluid Hollywood camera dynamics, night car pursuits, and luxury commercials from text.',
      badge: 'MINIMAX HAILUO AI • 4K VIDEO',
      videoThumbnailUrl: `${MEDIA_URL}/minimax_hero_player.jpg`,
      videoTitle: 'Hollywood Night Pursuit Sequence',
      videoDuration: '0:10 • 24 FPS',
      bodyText: 'Transform text prompts and still imagery into fluid 4K cinematic video. Our new Minimax Hailuo AI engine understands vehicle physics, water reflections, dynamic lighting, and character micro-expressions with zero morphing or artifact tearing.',
      videoLinkUrl: `${MEDIA_URL}/car-chase.mp4`,
      secondaryVideoThumbnail: `${MEDIA_URL}/minimax_zanzibar_hero.jpg`,
      secondaryVideoTitle: 'Zanzibar Oceanfront Luxury Commercial',
      featurePoints: [
        '243 coherent frames at 24fps with cinematic motion blur and realistic camera physics',
        'Advanced prompt understanding: night reflections, wet asphalt, tire smoke, and ocean caustics',
        'Export directly to 4K UHD MP4 with zero watermark in your Cosmic-Gen Studio dashboard',
      ],
      ctaText: 'Watch 4K Video & Try Studio',
      ctaUrl: BASE_URL,
    },
  },
  audio: {
    subject: 'Announcing Chatterbox Voice Studio - Human-Grade AI Speech & Voice Cloning',
    options: {
      headline: 'Chatterbox Voice Studio: Zero-Shot Voice Cloning & TTS',
      subtitle: 'Studio-grade 48kHz neural speech synthesis in English, Spanish, and West African languages.',
      badge: 'CHATTERBOX NEURAL VOICE',
      voiceModelName: 'Chatterbox Multilingual V2',
      sampleTitle: 'High-Fidelity Conversational Speech Sample',
      sampleDuration: '0:22',
      audioPreviewUrl: 'https://cosmic-gen.com/media/chatterbox_real_speech.wav',
      audioBannerUrl: `${MEDIA_URL}/chatterbox_voice_preview.jpg`,
      bodyText: 'Give your characters, digital marketing videos, and interactive apps a compelling human voice. Chatterbox generates emotional inflection, natural breath pauses, and authentic multilingual cadence with zero latency.',
      featurePoints: [
        'Lossless 48kHz studio audio output with zero digital robotic artifacts',
        'Instant 3-second voice cloning from any uploaded microphone or audio snippet',
        'Full dialect support: English (US/UK/NG), Spanish, French, Hausa, Yoruba, and Swahili',
      ],
      ctaText: 'Clone Your Voice in Studio',
      ctaUrl: BASE_URL,
    },
  },
  digest: {
    subject: 'Cosmic-Gen 2.0: Minimax 4K Video, Qwen 2.1 Photorealism & Chatterbox Audio',
    options: {
      headline: 'Cosmic-Gen 2.0: The Complete Multimodal AI Suite',
      subtitle: 'Minimax 4K Video, Qwen 2.1 Photorealism & Chatterbox Neural Speech in one unified platform.',
      badge: 'MAJOR SUITE RELEASE • ALL ENGINES LIVE',
      introText: 'We have officially upgraded Cosmic-Gen with three state-of-the-art generation engines. Whether you need Hollywood-level cinematic video, photorealistic high-fashion imagery, or studio-grade voice cloning, everything is now accessible in one workflow.',
      videoSection: {
        title: 'Minimax H3: 4K Cinematic AI Video',
        tagline: 'Hollywood Night Pursuit Sequence • 60 FPS Fluid Motion',
        thumbnailUrl: `${MEDIA_URL}/minimax_hero_player.jpg`,
        videoUrl: `${MEDIA_URL}/car-chase.mp4`,
        description: 'Generate hyper-realistic camera angles, fluid drifts, night rain reflections, and cohesive 24fps motion from a simple text prompt.',
      },
      imageSection: {
        title: 'Qwen Image 2.1: Photorealistic African Fashion & Posters',
        tagline: 'Lagos Street Style & Sharp In-Image Typography',
        imageUrl: `${MEDIA_URL}/qwen_fashion_card.jpg`,
        secondaryImageUrl: `${MEDIA_URL}/qwen_poster_card.jpg`,
        description: 'Experience perfect facial symmetry, rich fabric textures, and sharp rendered English text without distorted artifacts.',
      },
      audioSection: {
        title: 'Chatterbox Studio: 48kHz Neural Voice Cloning',
        tagline: 'Zero-Shot Speech Synthesis & Multilingual Dialects',
        previewImageUrl: `${MEDIA_URL}/chatterbox_voice_preview.jpg`,
        audioUrl: 'https://cosmic-gen.com/media/chatterbox_real_speech.wav',
        duration: '0:22',
        description: 'Clone voices from 3 seconds of reference audio or synthesize human-grade narration in English, Spanish, and West African languages.',
      },
      ctaText: 'Launch Studio & Claim 50 Free Credits',
      ctaUrl: BASE_URL,
    },
  },
};

const campaign = sampleData[campaignType] || sampleData.digest;

async function run() {
  if (isPreviewOnly) {
    let html = '';
    if (campaignType === 'video') {
      html = marketingTemplates.createVideoCampaign({ headline: campaign.options.headline, ...campaign.options });
    } else if (campaignType === 'audio') {
      html = marketingTemplates.createAudioCampaign({ headline: campaign.options.headline, ...campaign.options });
    } else if (campaignType === 'digest') {
      html = marketingTemplates.createMultiMediaDigest({ headline: campaign.options.headline, ...campaign.options });
    } else {
      html = marketingTemplates.createImageCampaign({ headline: campaign.options.headline, ...campaign.options });
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
