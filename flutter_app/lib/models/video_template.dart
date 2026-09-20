import 'package:flutter/material.dart';

/// Preset Video Template for high-quality motion and cinematic video generation.
class VideoTemplate {
  final String id;
  final String title;
  final String category;
  final String model;
  final String prompt;
  final String negativePrompt;
  final String aspectRatio;
  final int steps;
  final double cfgScale;
  final String duration;
  final int fps;
  final String cameraMotion;
  final List<Color> gradientColors;
  final List<String> tags;
  final String description;

  const VideoTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.model,
    required this.prompt,
    required this.negativePrompt,
    this.aspectRatio = '16:9',
    this.steps = 30,
    this.cfgScale = 5.0,
    this.duration = '4.0s',
    this.fps = 24,
    required this.cameraMotion,
    required this.gradientColors,
    required this.tags,
    required this.description,
  });

  /// Curated list of high-impact production templates across popular video genres
  static const List<VideoTemplate> curatedTemplates = [
    VideoTemplate(
      id: 'drone_cyberpunk_city',
      title: 'Neon Cyberpunk Drone Flyover',
      category: 'Cinematic Drone',
      model: 'Wan 2.1 T2V 1.3B',
      prompt:
          'Cinematic sweeping FPV drone shot soaring above a towering futuristic neon-lit cyberpunk metropolis at midnight. Rain-slicked glass skyscrapers, holographic billboards shimmering through dense atmospheric mist, flying transit vehicles, highly detailed 8k photorealistic reflections, dynamic smooth camera tilt downward.',
      negativePrompt:
          'flickering, jittery movements, sudden morphing, artifacts, low resolution, blurry edges, distorted geometric lines, static frame',
      aspectRatio: '16:9',
      steps: 30,
      cfgScale: 5.0,
      duration: '4.5s',
      fps: 24,
      cameraMotion: 'Dynamic Forward FPV Dive',
      gradientColors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF3B82F6), Color(0xFF06B6D4)],
      tags: ['FPV Drone', '4K HDR', 'Cyberpunk', 'Raytracing'],
      description: 'Futuristic night skyline flythrough with glowing neon reflections and volumetric fog.',
    ),
    VideoTemplate(
      id: 'luxury_product_spin',
      title: 'Luxury Watch 360° Studio Spin',
      category: 'Commercial 360',
      model: 'Wan 2.1 I2V 14B',
      prompt:
          'Macro commercial studio turntable shot of a luxury obsidian chronograph watch rotating smoothly 360 degrees. Golden rim bezel catching soft studio rim lighting, intricate mechanical gear motion visible, pristine dark slate background, shallow depth of field, slow-motion fluid luxury advertising aesthetic.',
      negativePrompt:
          'distorted details, wobbly rotation, scratches, flickering lighting, sudden zoom, deformed watch hands, low quality',
      aspectRatio: '1:1',
      steps: 32,
      cfgScale: 4.5,
      duration: '5.0s',
      fps: 30,
      cameraMotion: '360° Smooth Turntable Orbit',
      gradientColors: [Color(0xFF18181B), Color(0xFF27272A), Color(0xFFF59E0B), Color(0xFFD97706)],
      tags: ['Product Showcase', 'Macro 4K', 'Studio Lighting'],
      description: 'Ultra-clean commercial turntable rotation for luxury items, watches, and tech products.',
    ),
    VideoTemplate(
      id: 'anime_sakura_fight',
      title: 'Anime Shonen Energy Surge',
      category: 'Anime & VFX',
      model: 'Wan 2.1 T2V 1.3B',
      prompt:
          'High-octane anime action sequence in Makoto Shinkai style. A warrior with flowing silver hair channeling azure electric sparks into a glowing katana. Swirling pink sakura petals tearing through dynamic wind vortices, dramatic camera whip-pan orbit, cinematic speed ramps, vibrant saturated palette.',
      negativePrompt:
          'muddy colors, jerky frame drops, 3d uncanny valley, blurry hand drawings, flickering lines, bad anatomy',
      aspectRatio: '16:9',
      steps: 28,
      cfgScale: 6.0,
      duration: '3.5s',
      fps: 24,
      cameraMotion: 'Dynamic Whip Pan & Orbit',
      gradientColors: [Color(0xFF1E1B4B), Color(0xFF4C1D95), Color(0xFFEC4899), Color(0xFFF43F5E)],
      tags: ['Anime Style', 'VFX Burst', 'Action Ramp'],
      description: 'Fast-paced stylized anime combat rush with lightning aura and falling cherry blossoms.',
    ),
    VideoTemplate(
      id: 'character_walk_fashion',
      title: 'Haute Couture Runway Walk',
      category: 'Fashion & Character',
      model: 'Wan 2.2 Animate 14B',
      prompt:
          'Full-body cinematic medium shot of a high-fashion model strutting forward down an illuminated Paris runway. Flowing metallic silk gown undulating with realistic cloth physics, confident rhythmic gait, strobe flashes from the press pit, shallow telephoto bokeh, 8k fashion photography.',
      negativePrompt:
          'limping, deformed legs, disjointed limbs, morphing garment texture, floating feet, unnatural gait',
      aspectRatio: '9:16',
      steps: 25,
      cfgScale: 4.0,
      duration: '4.0s',
      fps: 24,
      cameraMotion: 'Tracking Backward Steadicam',
      gradientColors: [Color(0xFF172554), Color(0xFF1D4ED8), Color(0xFF60A5FA), Color(0xFF93C5FD)],
      tags: ['Vertical 9:16', 'Runway Strut', 'Cloth Physics'],
      description: 'Ideal for TikTok/Reels fashion videos, walking animations, and dynamic model poses.',
    ),
    VideoTemplate(
      id: 'nature_timelapse_aurora',
      title: 'Arctic Fjord Aurora Borealis',
      category: 'Nature & Wildlife',
      model: 'MiniMax-H3 Video+Audio',
      prompt:
          'Breathtaking 8k time-lapse video of vibrant emerald and violet Aurora Borealis dancing across deep arctic starry night sky over mirror-still fjord waters. Mountain peaks dusted with fresh snow, gentle water ripples reflecting ethereal celestial ribbons, synchronized ambient arctic wind acoustics.',
      negativePrompt:
          'compression banding, pixelated stars, static auroras, camera shake, overexposed highlights',
      aspectRatio: '16:9',
      steps: 35,
      cfgScale: 5.5,
      duration: '6.0s',
      fps: 30,
      cameraMotion: 'Slow Motion Pan-Right',
      gradientColors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF10B981), Color(0xFF06B6D4)],
      tags: ['MiniMax Audio', 'Time-lapse', 'Aurora 8K'],
      description: 'Celestial northern lights time-lapse with synchronized arctic atmospheric soundscape.',
    ),
    VideoTemplate(
      id: 'macro_water_splash_flower',
      title: 'Slow-Mo Water Droplet Bloom',
      category: 'Visual FX / Macro',
      model: 'Wan 2.1 I2V 14B',
      prompt:
          'Ultra high-speed phantom flex 1000fps slow-motion capture of a crystal-clear water droplet impacting a velvety crimson rose petal. Perfectly spherical splash crown forming, micro air bubbles refracting refracted studio spotlights, hyper-detailed surface tension dynamics.',
      negativePrompt:
          'flat textures, noisy water, low framerate stutter, digital distortion, unnatural splash physics',
      aspectRatio: '16:9',
      steps: 30,
      cfgScale: 4.5,
      duration: '4.0s',
      fps: 60,
      cameraMotion: 'Ultra Slow-Mo Static Macro',
      gradientColors: [Color(0xFF450A0A), Color(0xFF991B1B), Color(0xFFEF4444), Color(0xFFF87171)],
      tags: ['Phantom 1000fps', 'Fluid Dynamics', 'Macro 8K'],
      description: 'Hypnotic high-speed macro fluid explosion and droplet refraction.',
    ),
  ];
}
