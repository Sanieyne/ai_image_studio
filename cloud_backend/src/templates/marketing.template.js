/**
 * Cosmic-Gen Marketing Email Templates
 * Responsive, client-compatible (Gmail, Apple Mail, Outlook), obsidian-themed templates
 * supporting image showcases, video preview cards, and audio/voice players.
 */

/**
 * Common styles and layout wrapper for Cosmic-Gen marketing emails.
 */
function renderBaseLayout({ preheader, headerTitle, headerSubtitle, contentHtml, ctaText, ctaUrl, unsubscribeUrl }) {
  const currentYear = new Date().getFullYear();
  const ctaButtonHtml = ctaText && ctaUrl ? `
    <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin: 28px auto 0 auto;">
      <tr>
        <td align="center" style="border-radius: 10px; background: #6366f1; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 50%, #d946ef 100%);">
          <a href="${ctaUrl}" target="_blank" style="display: inline-block; padding: 14px 34px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; font-size: 15px; font-weight: 700; color: #ffffff; text-decoration: none; border-radius: 10px; letter-spacing: 0.3px;">
            ${ctaText} &rarr;
          </a>
        </td>
      </tr>
    </table>
  ` : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <title>${headerTitle || 'Cosmic-Gen AI'}</title>
  <style type="text/css">
    body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
    table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
    img { -ms-interpolation-mode: bicubic; border: 0; outline: none; text-decoration: none; }
    body { margin: 0 !important; padding: 0 !important; width: 100% !important; background-color: #0b0f19; }
    @media screen and (max-width: 600px) {
      .email-container { width: 100% !important; margin: auto !important; }
      .fluid { max-width: 100% !important; height: auto !important; }
      .mobile-p-20 { padding: 20px !important; }
      .headline-mobile { font-size: 24px !important; line-height: 32px !important; }
    }
  </style>
</head>
<body style="margin: 0; padding: 0; background-color: #0b0f19; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #e2e8f0;">

  <!-- Preheader preview text (visible in inbox summary, hidden in email body) -->
  <div style="display: none; font-size: 1px; color: #0b0f19; line-height: 1px; max-height: 0px; max-width: 0px; opacity: 0; overflow: hidden;">
    ${preheader || headerTitle || 'Latest from Cosmic-Gen AI Studio'}
  </div>

  <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #0b0f19;">
    <tr>
      <td align="center" style="padding: 32px 16px;">
        <!-- Email Container (max 600px) -->
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="600" class="email-container" style="max-width: 600px; width: 100%; background-color: #121826; border: 1px solid #1f293d; border-radius: 16px; overflow: hidden; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);">
          
          <!-- Brand Header -->
          <tr>
            <td style="padding: 32px 32px 20px 32px; text-align: center; background: radial-gradient(circle at top, rgba(99, 102, 241, 0.15) 0%, transparent 70%);">
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
                <tr>
                  <td align="center">
                    <div style="display: inline-block; padding: 6px 14px; background: rgba(99, 102, 241, 0.15); border: 1px solid rgba(99, 102, 241, 0.35); border-radius: 9999px; margin-bottom: 12px;">
                      <span style="font-size: 11px; font-weight: 700; color: #a5b4fc; text-transform: uppercase; letter-spacing: 1.5px;">✦ Cosmic-Gen AI</span>
                    </div>
                    <h1 class="headline-mobile" style="margin: 0 0 6px 0; font-size: 28px; font-weight: 800; color: #ffffff; letter-spacing: -0.5px; line-height: 36px;">
                      ${headerTitle}
                    </h1>
                    ${headerSubtitle ? `<p style="margin: 0; font-size: 14px; color: #94a3b8; line-height: 22px;">${headerSubtitle}</p>` : ''}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Main Content -->
          <tr>
            <td style="padding: 10px 32px 32px 32px;" class="mobile-p-20">
              ${contentHtml}
              ${ctaButtonHtml}
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 24px 32px; background-color: #0d121d; border-top: 1px solid #1a2234; text-align: center;">
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
                <tr>
                  <td align="center">
                    <p style="margin: 0 0 10px 0; font-size: 13px; font-weight: 600; color: #cbd5e1;">
                      Cosmic-Gen AI Creative Studio
                    </p>
                    <p style="margin: 0 0 14px 0; font-size: 11px; color: #64748b; line-height: 18px;">
                      Empowering creators with real-time neural image, video & audio generation.
                      <br>Questions? Email us directly at <a href="mailto:support@cosmic-gen.com" style="color: #818cf8; text-decoration: none;">support@cosmic-gen.com</a>
                    </p>
                    <p style="margin: 0; font-size: 11px; color: #475569;">
                      &copy; ${currentYear} Cosmic-Gen &bull; <a href="https://cosmic-gen.com" style="color: #64748b; text-decoration: none;">cosmic-gen.com</a>
                      ${unsubscribeUrl ? ` &bull; <a href="${unsubscribeUrl}" style="color: #64748b; text-decoration: underline;">Unsubscribe</a>` : ''}
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>`;
}

export const marketingTemplates = {
  /**
   * 1. Image Showcase Campaign Template
   * Ideal for highlighting newly released AI models (e.g. Flux Kontext, Qwen, SDXL).
   */
  createImageCampaign({
    headline,
    subtitle,
    badge = 'New AI Model',
    bodyText,
    imageUrl,
    imageAlt = 'Cosmic-Gen AI Image',
    imageCaption,
    featurePoints = [],
    ctaText = 'Generate with Model',
    ctaUrl = 'https://cosmic-gen.com',
  }) {
    const featuresHtml = featurePoints.length > 0 ? `
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-top: 24px; background: rgba(255, 255, 255, 0.02); border: 1px solid #1f293d; border-radius: 12px; padding: 16px;">
        ${featurePoints.map(f => `
          <tr>
            <td style="padding: 6px 12px; font-size: 13.5px; color: #e2e8f0; line-height: 20px;">
              <span style="color: #818cf8; font-weight: bold; margin-right: 6px;">✔</span> ${f}
            </td>
          </tr>
        `).join('')}
      </table>
    ` : '';

    const contentHtml = `
      <div style="text-align: center; margin-bottom: 20px;">
        <span style="display: inline-block; padding: 4px 10px; background: rgba(56, 189, 248, 0.12); border: 1px solid rgba(56, 189, 248, 0.3); border-radius: 6px; font-size: 11px; font-weight: 700; color: #38bdf8; text-transform: uppercase;">
          ${badge}
        </span>
      </div>

      <!-- Hero Image -->
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 20px;">
        <tr>
          <td align="center">
            <div style="border-radius: 12px; overflow: hidden; border: 1px solid #2d3748; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);">
              <img src="${imageUrl}" alt="${imageAlt}" width="536" class="fluid" style="display: block; width: 100%; max-width: 536px; height: auto; border-radius: 12px;" />
            </div>
            ${imageCaption ? `<p style="margin: 8px 0 0 0; font-size: 12px; color: #94a3b8; font-style: italic;">${imageCaption}</p>` : ''}
          </td>
        </tr>
      </table>

      <!-- Copy -->
      <p style="font-size: 15px; line-height: 24px; color: #cbd5e1; margin: 0 0 16px 0;">
        ${bodyText}
      </p>

      ${featuresHtml}
    `;

    return renderBaseLayout({
      preheader: headline,
      headerTitle: headline,
      headerSubtitle: subtitle,
      contentHtml,
      ctaText,
      ctaUrl,
    });
  },

  /**
   * 2. Video Preview Campaign Template
   * Renders a video card with a prominent overlay play button that drives clicks to video demo.
   */
  createVideoCampaign({
    headline,
    subtitle,
    badge = 'Video Generation',
    videoThumbnailUrl,
    videoDuration = '0:30',
    bodyText,
    videoLinkUrl = 'https://cosmic-gen.com/gallery',
    videoTitle = 'Cosmic-Gen Neural Video Showcase',
    featurePoints = [],
    ctaText = 'Watch Full Video Demo',
    ctaUrl,
  }) {
    const playTargetUrl = ctaUrl || videoLinkUrl;

    const contentHtml = `
      <div style="text-align: center; margin-bottom: 20px;">
        <span style="display: inline-block; padding: 4px 10px; background: rgba(244, 63, 94, 0.12); border: 1px solid rgba(244, 63, 94, 0.3); border-radius: 6px; font-size: 11px; font-weight: 700; color: #fb7185; text-transform: uppercase;">
          🎬 ${badge}
        </span>
      </div>

      <!-- Video Preview Card with Play Overlay -->
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 20px;">
        <tr>
          <td align="center">
            <a href="${playTargetUrl}" target="_blank" style="display: block; text-decoration: none; position: relative;">
              <div style="border-radius: 12px; overflow: hidden; border: 1px solid #334155; background: #0f172a; position: relative;">
                <img src="${videoThumbnailUrl}" alt="${videoTitle}" width="536" class="fluid" style="display: block; width: 100%; max-width: 536px; height: auto; opacity: 0.88;" />
                
                <!-- Simulated Play Button Banner -->
                <div style="background: linear-gradient(180deg, transparent 0%, rgba(15, 23, 42, 0.95) 100%); padding: 18px 20px; text-align: left;">
                  <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
                    <tr>
                      <td width="48" valign="middle">
                        <div style="width: 42px; height: 42px; border-radius: 50%; background: #e11d48; text-align: center; line-height: 42px; font-size: 18px; color: #ffffff; box-shadow: 0 0 16px rgba(225, 29, 72, 0.6);">
                          &#9658;
                        </div>
                      </td>
                      <td valign="middle" style="padding-left: 14px;">
                        <div style="font-size: 14px; font-weight: 700; color: #ffffff;">${videoTitle}</div>
                        <div style="font-size: 12px; color: #94a3b8;">Click to play preview &bull; ${videoDuration}</div>
                      </td>
                    </tr>
                  </table>
                </div>

              </div>
            </a>
          </td>
        </tr>
      </table>

      <!-- Copy -->
      <p style="font-size: 15px; line-height: 24px; color: #cbd5e1; margin: 0 0 16px 0;">
        ${bodyText}
      </p>

      ${featurePoints.length > 0 ? `
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-top: 16px; background: rgba(255, 255, 255, 0.02); border: 1px solid #1f293d; border-radius: 12px; padding: 16px;">
          ${featurePoints.map(f => `
            <tr>
              <td style="padding: 6px 12px; font-size: 13.5px; color: #e2e8f0; line-height: 20px;">
                <span style="color: #fb7185; font-weight: bold; margin-right: 6px;">▶</span> ${f}
              </td>
            </tr>
          `).join('')}
        </table>
      ` : ''}
    `;

    return renderBaseLayout({
      preheader: headline,
      headerTitle: headline,
      headerSubtitle: subtitle,
      contentHtml,
      ctaText,
      ctaUrl: playTargetUrl,
    });
  },

  /**
   * 3. Audio & Voice Campaign Template
   * Showcases speech generation (Chatterbox, Breeze TTS), voice cloning, and audio samples.
   */
  createAudioCampaign({
    headline,
    subtitle,
    badge = 'Voice & Audio AI',
    voiceModelName = 'Chatterbox Multilingual',
    sampleTitle = 'English & Spanish Expressive Speech Sample',
    bodyText,
    sampleDuration = '0:18',
    audioPreviewUrl = 'https://cosmic-gen.com/media/chatterbox_real_speech.wav',
    featurePoints = [],
    ctaText = 'Try Voice Studio',
    ctaUrl = 'https://cosmic-gen.com',
  }) {
    const contentHtml = `
      <div style="text-align: center; margin-bottom: 20px;">
        <span style="display: inline-block; padding: 4px 10px; background: rgba(168, 85, 247, 0.12); border: 1px solid rgba(168, 85, 247, 0.3); border-radius: 6px; font-size: 11px; font-weight: 700; color: #c084fc; text-transform: uppercase;">
          🎙️ ${badge}
        </span>
      </div>

      <!-- Styled Audio Player Card -->
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 24px; background: linear-gradient(135deg, #1e1b4b 0%, #0f172a 100%); border: 1px solid #3730a3; border-radius: 14px; padding: 22px;">
        <tr>
          <td>
            <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
              <tr>
                <td width="52" valign="middle">
                  <a href="${audioPreviewUrl}" target="_blank" style="text-decoration: none;">
                    <div style="width: 48px; height: 48px; border-radius: 50%; background: #6366f1; text-align: center; line-height: 48px; font-size: 20px; color: #ffffff; box-shadow: 0 0 16px rgba(99, 102, 241, 0.6);">
                      &#9658;
                    </div>
                  </a>
                </td>
                <td valign="middle" style="padding-left: 16px;">
                  <div style="font-size: 11px; font-weight: 700; color: #a5b4fc; text-transform: uppercase; letter-spacing: 0.5px;">${voiceModelName}</div>
                  <div style="font-size: 15px; font-weight: 700; color: #ffffff; margin-top: 2px;">${sampleTitle}</div>
                  <div style="font-size: 12px; color: #94a3b8; margin-top: 2px;">Length: ${sampleDuration} &bull; Crystal-clear 24kHz neural speech</div>
                </td>
              </tr>
            </table>

            <!-- Simulated Modern Waveform Graphic -->
            <div style="margin-top: 18px; padding: 12px 16px; background: rgba(0, 0, 0, 0.3); border-radius: 8px; text-align: center;">
              <span style="font-size: 20px; letter-spacing: 3px; color: #818cf8; font-family: monospace;">
                &#9601;&#9603;&#9605;&#9607;&#9604;&#9602;&#9606;&#9608;&#9605;&#9603;&#9606;&#9604;&#9607;&#9608;&#9605;&#9603;&#9602;&#9606;&#9607;&#9605;&#9603;&#9601;
              </span>
              <div style="margin-top: 8px;">
                <a href="${audioPreviewUrl}" target="_blank" style="font-size: 12px; color: #38bdf8; text-decoration: none; font-weight: 600;">
                  Click here to listen to sample audio &rarr;
                </a>
              </div>
            </div>

          </td>
        </tr>
      </table>

      <!-- Copy -->
      <p style="font-size: 15px; line-height: 24px; color: #cbd5e1; margin: 0 0 16px 0;">
        ${bodyText}
      </p>

      ${featurePoints.length > 0 ? `
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-top: 16px; background: rgba(255, 255, 255, 0.02); border: 1px solid #1f293d; border-radius: 12px; padding: 16px;">
          ${featurePoints.map(f => `
            <tr>
              <td style="padding: 6px 12px; font-size: 13.5px; color: #e2e8f0; line-height: 20px;">
                <span style="color: #a855f7; font-weight: bold; margin-right: 6px;">♪</span> ${f}
              </td>
            </tr>
          `).join('')}
        </table>
      ` : ''}
    `;

    return renderBaseLayout({
      preheader: headline,
      headerTitle: headline,
      headerSubtitle: subtitle,
      contentHtml,
      ctaText,
      ctaUrl,
    });
  },

  /**
   * 4. Multi-Media Announcement Digest
   * Combines Image, Video, and Voice in a single high-impact email newsletter.
   */
  createMultiMediaDigest({
    headline,
    subtitle,
    introText,
    imageSection,
    videoSection,
    audioSection,
    ctaText = 'Explore Cosmic-Gen Studio',
    ctaUrl = 'https://cosmic-gen.com',
  }) {
    let sectionsHtml = '';

    if (imageSection) {
      sectionsHtml += `
        <div style="margin-top: 24px; padding: 18px; background: #0f172a; border: 1px solid #1e293b; border-radius: 12px;">
          <div style="font-size: 11px; font-weight: 700; color: #38bdf8; text-transform: uppercase; margin-bottom: 6px;">🖼️ Image Studio</div>
          <div style="font-size: 16px; font-weight: 700; color: #ffffff; margin-bottom: 12px;">${imageSection.title}</div>
          <img src="${imageSection.imageUrl}" alt="${imageSection.title}" width="500" class="fluid" style="width: 100%; border-radius: 8px; margin-bottom: 10px;" />
          <p style="font-size: 13.5px; color: #94a3b8; line-height: 20px; margin: 0 0 8px 0;">${imageSection.description}</p>
        </div>
      `;
    }

    if (videoSection) {
      sectionsHtml += `
        <div style="margin-top: 20px; padding: 18px; background: #0f172a; border: 1px solid #1e293b; border-radius: 12px;">
          <div style="font-size: 11px; font-weight: 700; color: #fb7185; text-transform: uppercase; margin-bottom: 6px;">🎬 Video Engine</div>
          <div style="font-size: 16px; font-weight: 700; color: #ffffff; margin-bottom: 12px;">${videoSection.title}</div>
          <a href="${videoSection.videoUrl || ctaUrl}" target="_blank" style="text-decoration: none; display: block;">
            <div style="position: relative; border-radius: 8px; overflow: hidden;">
              <img src="${videoSection.thumbnailUrl}" alt="${videoSection.title}" width="500" class="fluid" style="width: 100%; border-radius: 8px; display: block;" />
              <div style="padding: 10px 14px; background: rgba(15, 23, 42, 0.9); font-size: 12px; color: #ffffff; font-weight: 600;">
                &#9658; Click to watch neural video preview
              </div>
            </div>
          </a>
          <p style="font-size: 13.5px; color: #94a3b8; line-height: 20px; margin: 10px 0 0 0;">${videoSection.description}</p>
        </div>
      `;
    }

    if (audioSection) {
      sectionsHtml += `
        <div style="margin-top: 20px; padding: 18px; background: #0f172a; border: 1px solid #1e293b; border-radius: 12px;">
          <div style="font-size: 11px; font-weight: 700; color: #c084fc; text-transform: uppercase; margin-bottom: 6px;">🎙️ Voice & Audio</div>
          <div style="font-size: 16px; font-weight: 700; color: #ffffff; margin-bottom: 8px;">${audioSection.title}</div>
          <p style="font-size: 13.5px; color: #94a3b8; line-height: 20px; margin: 0 0 12px 0;">${audioSection.description}</p>
          <div style="padding: 12px 14px; background: rgba(99, 102, 241, 0.1); border: 1px solid rgba(99, 102, 241, 0.3); border-radius: 8px;">
            <a href="${audioSection.audioUrl || ctaUrl}" target="_blank" style="font-size: 13px; font-weight: 600; color: #818cf8; text-decoration: none;">
              &#9658; Listen to sample voice audio (${audioSection.duration || '0:15'}) &rarr;
            </a>
          </div>
        </div>
      `;
    }

    const contentHtml = `
      <p style="font-size: 15px; line-height: 24px; color: #cbd5e1; margin: 0 0 16px 0;">
        ${introText}
      </p>
      ${sectionsHtml}
    `;

    return renderBaseLayout({
      preheader: headline,
      headerTitle: headline,
      headerSubtitle: subtitle,
      contentHtml,
      ctaText,
      ctaUrl,
    });
  },
};
