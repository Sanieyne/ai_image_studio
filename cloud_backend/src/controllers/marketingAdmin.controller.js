import { User } from '../models/User.js';
import { Generation } from '../models/Generation.js';
import { MarketingCampaign } from '../models/MarketingCampaign.js';
import { emailService } from '../services/email.service.js';
import { marketingTemplates } from '../templates/marketing.template.js';

const MEDIA_URL = 'https://cosmic-gen.com/media/marketing';
const BASE_URL = 'https://cosmic-gen.com';

// Emoji regex to prevent Truehost SUBJECT_HAS_EMOJI antispam rejection (554 5.7.1)
const EMOJI_REGEX = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}]/u;

const DEFAULT_PRESETS = {
  digest: {
    name: 'Cosmic-Gen 2.0 Multi-Media Suite Digest',
    subject: 'Cosmic-Gen 2.0: Minimax 4K Video, Qwen 2.1 Photorealism & Chatterbox Audio',
    badge: 'MAJOR SUITE RELEASE • ALL ENGINES LIVE',
    headline: 'Cosmic-Gen 2.0: The Complete Multimodal AI Suite',
    subtitle: 'Minimax 4K Video, Qwen 2.1 Photorealism & Chatterbox Neural Speech in one unified platform.',
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
  video: {
    name: 'Minimax H3 4K Video Launch',
    subject: 'Hollywood Motion: Minimax H3 4K Video Generation is Here',
    badge: 'MINIMAX HAILUO AI • 4K VIDEO',
    headline: 'Minimax H3 Video Engine: Cinematic 4K AI Video is Here',
    subtitle: 'Render fluid Hollywood camera dynamics, night car pursuits, and luxury commercials from text.',
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
  image: {
    name: 'Qwen Image 2.1 Photorealism Showcase',
    subject: 'Photorealism Redefined: Qwen Image 2.1 is Now Live on Cosmic-Gen',
    badge: 'QWEN IMAGE 2.1 • PHOTOREALISM',
    headline: 'Photorealism Redefined: Qwen Image 2.1 is Live',
    subtitle: 'Flawless human anatomy, authentic Lagos street fashion, and sharp in-image typography.',
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
  audio: {
    name: 'Chatterbox Neural Voice Studio Announcement',
    subject: 'Announcing Chatterbox Voice Studio - Human-Grade AI Speech & Voice Cloning',
    badge: 'CHATTERBOX NEURAL VOICE',
    headline: 'Chatterbox Voice Studio: Zero-Shot Voice Cloning & TTS',
    subtitle: 'Studio-grade 48kHz neural speech synthesis in English, Spanish, and West African languages.',
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
};

/**
 * 1. GET /api/v1/admin/marketing/stats
 * Overview numbers: registered users, verified users, creators, campaigns sent
 */
export async function getMarketingStats(req, res, next) {
  try {
    const [totalUsers, verifiedUsers, totalCampaigns, activeCreators] = await Promise.all([
      User.countDocuments({ email: { $exists: true, $ne: '' } }),
      User.countDocuments({ isEmailVerified: true }),
      MarketingCampaign.countDocuments(),
      Generation.distinct('userId').then(u => u.length).catch(() => 0),
    ]);

    res.status(200).json({
      success: true,
      data: {
        totalUsers,
        verifiedUsers,
        activeCreators,
        totalCampaigns,
        smtp: {
          host: 'workplaceproemail.com',
          port: 465,
          sender: 'marketing@cosmic-gen.com',
          status: 'connected',
        },
      },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * 2. GET /api/v1/admin/marketing/presets
 * Returns available template presets and media library assets
 */
export async function getMarketingPresets(req, res) {
  res.status(200).json({
    success: true,
    data: {
      presets: DEFAULT_PRESETS,
      mediaLibrary: [
        { label: 'Minimax 4K Video Player Poster', url: `${MEDIA_URL}/minimax_hero_player.jpg`, type: 'video_poster' },
        { label: 'Minimax Zanzibar Luxury Resort', url: `${MEDIA_URL}/minimax_zanzibar_hero.jpg`, type: 'video_poster' },
        { label: 'Minimax 4K Video File (MP4)', url: `${MEDIA_URL}/car-chase.mp4`, type: 'video' },
        { label: 'Qwen Lagos Ankara Fashion (Best)', url: `${MEDIA_URL}/qwen_fashion_card.jpg`, type: 'image' },
        { label: 'Qwen Sci-Fi Typography Poster', url: `${MEDIA_URL}/qwen_poster_card.jpg`, type: 'image' },
        { label: 'Qwen African Creator Portrait', url: `${MEDIA_URL}/qwen_creator_card.jpg`, type: 'image' },
        { label: 'Chatterbox Neural Waveform Player', url: `${MEDIA_URL}/chatterbox_voice_preview.jpg`, type: 'audio_poster' },
        { label: 'Chatterbox Audio WAV Sample', url: 'https://cosmic-gen.com/media/chatterbox_real_speech.wav', type: 'audio' },
      ],
    },
  });
}

/**
 * Helper to render HTML from type and options
 */
function renderCampaignHtml(type, options = {}) {
  const headline = options.headline || options.subject || 'Cosmic-Gen AI Creative Studio';
  switch (type) {
    case 'video':
      return marketingTemplates.createVideoCampaign({ headline, ...options });
    case 'image':
      return marketingTemplates.createImageCampaign({ headline, ...options });
    case 'audio':
      return marketingTemplates.createAudioCampaign({ headline, ...options });
    case 'digest':
    default:
      return marketingTemplates.createMultiMediaDigest({ headline, ...options });
  }
}

/**
 * 3. POST /api/v1/admin/marketing/preview
 * Renders HTML for live preview in the Admin Console
 */
export async function previewMarketingCampaign(req, res, next) {
  try {
    const { type = 'digest', options = {} } = req.body;
    const html = renderCampaignHtml(type, options);

    res.status(200).json({
      success: true,
      data: { html },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * 4. POST /api/v1/admin/marketing/send-test
 * Sends a single test marketing email to a specified test address
 */
export async function sendTestMarketingEmail(req, res, next) {
  try {
    const { testEmail, type = 'digest', subject, options = {} } = req.body;

    if (!testEmail || !testEmail.includes('@')) {
      return res.status(400).json({ success: false, message: 'Valid test email address is required.' });
    }

    if (!subject || !subject.trim()) {
      return res.status(400).json({ success: false, message: 'Subject line is required.' });
    }

    if (EMOJI_REGEX.test(subject)) {
      return res.status(400).json({
        success: false,
        message: 'Truehost antispam rules forbid emojis in the email subject. Please remove emojis from the subject line.',
      });
    }

    const result = await emailService.sendMarketingCampaign({
      to: testEmail,
      from: 'Cosmic-Gen <marketing@cosmic-gen.com>',
      subject: subject.trim(),
      type,
      options,
    });

    // Record test dispatch
    await MarketingCampaign.create({
      subject: subject.trim(),
      type,
      sender: 'Cosmic-Gen <marketing@cosmic-gen.com>',
      badge: options.badge,
      headline: options.headline,
      subtitle: options.subtitle,
      bodyText: options.bodyText || options.introText,
      options,
      targetAudience: 'test_only',
      recipientCount: 1,
      recipients: [testEmail],
      status: 'sent',
      results: [{ email: testEmail, status: 'sent', messageId: result.messageId }],
      sentBy: req.user?._id,
      sentByEmail: req.user?.email,
      sentAt: new Date(),
    });

    res.status(200).json({
      success: true,
      message: `Test email successfully dispatched to ${testEmail}`,
      data: {
        messageId: result.messageId,
        accepted: result.accepted,
      },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * 5. POST /api/v1/admin/marketing/broadcast
 * Broadcasts to a chosen audience segment: all_users, verified_users, or custom list
 */
export async function broadcastMarketingCampaign(req, res, next) {
  try {
    const { type = 'digest', subject, options = {}, targetAudience = 'verified_users', customRecipients = [] } = req.body;

    if (!subject || !subject.trim()) {
      return res.status(400).json({ success: false, message: 'Subject line is required.' });
    }

    if (EMOJI_REGEX.test(subject)) {
      return res.status(400).json({
        success: false,
        message: 'Truehost antispam rules forbid emojis in the email subject. Please remove emojis from the subject line.',
      });
    }

    let recipientEmails = [];
    if (targetAudience === 'verified_users') {
      const users = await User.find({ isEmailVerified: true }, 'email');
      recipientEmails = users.map(u => u.email).filter(Boolean);
    } else if (targetAudience === 'all_users') {
      const users = await User.find({ email: { $exists: true, $ne: '' } }, 'email');
      recipientEmails = users.map(u => u.email).filter(Boolean);
    } else if (targetAudience === 'custom_list') {
      recipientEmails = Array.isArray(customRecipients) ? customRecipients.filter(e => e && e.includes('@')) : [];
    }

    // Deduplicate
    recipientEmails = [...new Set(recipientEmails.map(e => e.trim().toLowerCase()))];

    if (recipientEmails.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No valid recipients found for the selected audience segment.',
      });
    }

    // Create campaign record
    const campaign = await MarketingCampaign.create({
      subject: subject.trim(),
      type,
      sender: 'Cosmic-Gen <marketing@cosmic-gen.com>',
      badge: options.badge,
      headline: options.headline,
      subtitle: options.subtitle,
      bodyText: options.bodyText || options.introText,
      options,
      targetAudience,
      recipientCount: recipientEmails.length,
      recipients: recipientEmails,
      status: 'queued',
      results: [],
      sentBy: req.user?._id,
      sentByEmail: req.user?.email,
      sentAt: new Date(),
    });

    // Execute dispatch in background batches so the HTTP response returns promptly
    (async () => {
      const results = [];
      let successCount = 0;
      let failCount = 0;

      for (const email of recipientEmails) {
        try {
          const res = await emailService.sendMarketingCampaign({
            to: email,
            from: 'Cosmic-Gen <marketing@cosmic-gen.com>',
            subject: subject.trim(),
            type,
            options,
          });
          results.push({ email, status: 'sent', messageId: res.messageId });
          successCount++;
        } catch (err) {
          results.push({ email, status: 'failed', error: err.message });
          failCount++;
        }
        // Small 300ms pause between sends to be gentle with SMTP connection limits
        await new Promise(r => setTimeout(r, 300));
      }

      const finalStatus = failCount === 0 ? 'sent' : successCount > 0 ? 'partial_failure' : 'failed';
      await MarketingCampaign.findByIdAndUpdate(campaign._id, {
        status: finalStatus,
        results,
      });
    })().catch(err => {
      console.error('[MarketingBroadcast] Background dispatch error:', err);
    });

    res.status(200).json({
      success: true,
      message: `Campaign queued for ${recipientEmails.length} recipients. Dispatch in progress.`,
      data: {
        campaignId: campaign._id,
        recipientCount: recipientEmails.length,
        status: 'queued',
      },
    });
  } catch (err) {
    next(err);
  }
}

/**
 * 6. GET /api/v1/admin/marketing/history
 * Returns paginated list of past marketing dispatches
 */
export async function getMarketingCampaignHistory(req, res, next) {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 15));
    const skip = (page - 1) * limit;

    const [campaigns, total] = await Promise.all([
      MarketingCampaign.find()
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      MarketingCampaign.countDocuments(),
    ]);

    res.status(200).json({
      success: true,
      data: {
        campaigns,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      },
    });
  } catch (err) {
    next(err);
  }
}
