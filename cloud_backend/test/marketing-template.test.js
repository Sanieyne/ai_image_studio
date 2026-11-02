import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { marketingTemplates } from '../src/templates/marketing.template.js';

describe('Marketing Email Templates', () => {
  it('renders Multi-Media Digest with Minimax, Qwen, and Chatterbox sections', () => {
    const html = marketingTemplates.createMultiMediaDigest({
      headline: 'Cosmic-Gen 2.0 Launch',
    });

    assert.ok(html.includes('<!DOCTYPE html PUBLIC'), 'Must include valid doctype');
    assert.ok(html.includes('COSMIC'), 'Must include brand header');
    assert.ok(html.includes('MAJOR SUITE RELEASE'), 'Must include suite badge');
    assert.ok(html.includes('minimax_hero_player.jpg'), 'Must link Minimax video hero card');
    assert.ok(html.includes('qwen_fashion_card.jpg'), 'Must link Qwen fashion card');
    assert.ok(html.includes('qwen_poster_card.jpg'), 'Must link Qwen poster card');
    assert.ok(html.includes('chatterbox_voice_preview.jpg'), 'Must link Chatterbox preview');
    assert.ok(html.includes('car-chase.mp4'), 'Must link directly to 4K demo');
    assert.ok(html.includes('50 Free Credits'), 'Must feature the 50 free credits bonus');
  });

  it('renders Minimax Video Campaign with player overlay and 4K stream action', () => {
    const html = marketingTemplates.createVideoCampaign({
      headline: 'Hollywood Video Motion',
      videoThumbnailUrl: 'https://cosmic-gen.com/media/marketing/minimax_hero_player.jpg',
      videoTitle: 'Hollywood Night Pursuit',
    });

    assert.ok(html.includes('MINIMAX HAILUO AI'), 'Must include Minimax badge');
    assert.ok(html.includes('STREAM DEMO &rarr;'), 'Must have stream action');
    assert.ok(html.includes('Hollywood Night Pursuit'), 'Must have video title');
  });

  it('renders Qwen 2.1 Image Campaign with photorealism highlights', () => {
    const html = marketingTemplates.createImageCampaign({
      headline: 'Qwen 2.1 Launch',
      imageUrl: 'https://cosmic-gen.com/media/marketing/qwen_fashion_card.jpg',
    });

    assert.ok(html.includes('QWEN IMAGE 2.1'), 'Must include Qwen badge');
    assert.ok(html.includes('PROMPT ADHERENCE'), 'Must show adherence metric');
    assert.ok(html.includes('qwen_fashion_card.jpg'), 'Must include image');
  });

  it('renders Chatterbox Audio Campaign with waveform preview', () => {
    const html = marketingTemplates.createAudioCampaign({
      headline: 'Chatterbox TTS Launch',
    });

    assert.ok(html.includes('CHATTERBOX NEURAL VOICE'), 'Must include Chatterbox badge');
    assert.ok(html.includes('chatterbox_real_speech.wav'), 'Must include wav link');
    assert.ok(html.includes('PLAY AUDIO ▶'), 'Must include play button action');
  });
});
