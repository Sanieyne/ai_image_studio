import 'package:flutter/material.dart';

/// Preset Image Template for high-quality photorealistic and stylized image generation.
class ImageTemplate {
  final String id;
  final String title;
  final String category;
  final String model;
  final String prompt;
  final String negativePrompt;
  final String aspectRatio;
  final int steps;
  final double cfgScale;
  final double strength;
  final List<Color> gradientColors;
  final List<String> tags;
  final String description;

  const ImageTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.model,
    required this.prompt,
    required this.negativePrompt,
    this.aspectRatio = '1:1',
    this.steps = 25,
    this.cfgScale = 4.0,
    this.strength = 0.75,
    required this.gradientColors,
    required this.tags,
    required this.description,
  });

  bool get isTryOnModel => model.contains('FASHN');

  bool get requiresImageAttachment => isTryOnModel;
  bool get requiresAttachment => requiresImageAttachment;

  IconData get icon {
    switch (category) {
      case 'Portrait & Character':
        return Icons.face_retouching_natural_rounded;
      case 'Product & Commercial':
        return Icons.shopping_bag_outlined;
      case 'Anime & Fantasy':
        return Icons.auto_awesome_rounded;
      case 'Fashion & Try-On':
        return Icons.checkroom_rounded;
      case 'Architecture':
        return Icons.apartment_rounded;
      case 'Nature & Macro':
        return Icons.nature_people_rounded;
      case 'Sci-Fi & 3D':
        return Icons.view_in_ar_rounded;
      case 'Cinematic Still':
        return Icons.camera_indoor_rounded;
      default:
        return Icons.image_rounded;
    }
  }

  String get attachmentBadgeLabel {
    if (isTryOnModel) return 'Requires Person & Garment (Try-On)';
    return 'Text-to-Image (Ready)';
  }

  String get attachmentGuidance {
    if (isTryOnModel) {
      return 'Virtual Try-On requires both a Person photo and a Garment photo. Please attach both using the buttons below.';
    }
    return 'Settings loaded (CFG: $cfgScale, Steps: $steps). Click Generate to create!';
  }

  /// Curated list of high-impact production templates across popular image genres
  static const List<ImageTemplate> curatedTemplates = [
    ImageTemplate(
      id: 'qwen_neon_typography_2k',
      title: 'Qwen 2K Neon Glass Pavilion & Typography',
      category: 'Architecture & Nature',
      model: 'Qwen-Image 2.1',
      prompt:
          'Ultra-high-definition 2K photograph of a minimalist Tokyo glass pavilion at dusk. Bold glowing neon typography signage that reads "QWEN 2.1 STUDIO" seamlessly integrated into the architectural glass facade. Transparent reflections of twilight city lights on polished marble flooring, wet asphalt reflections, hyper-sharp textures and pristine typography clarity, 8k professional architectural photography.',
      negativePrompt:
          'blurry, illegible letters, deformed text, low resolution, artifacts, noisy',
      aspectRatio: '16:9',
      steps: 40,
      cfgScale: 1.0,
      strength: 0.75,
      gradientColors: [Color(0xFF0C4A6E), Color(0xFF0284C7), Color(0xFF38BDF8), Color(0xFFF43F5E)],
      tags: ['Qwen 2.1', '2K Resolution', 'Typography', 'Glass & Neon'],
      description: 'Ultra-crisp 2K architectural rendering featuring flawless integrated typography and glass transparency.',
    ),
    ImageTemplate(
      id: 'cyberpunk_neon_portrait',
      title: 'Cyberpunk Neon Holographic Portrait',
      category: 'Portrait & Character',
      model: 'FLUX.1 Kontext [dev]',
      prompt:
          'Intimate cinematic portrait of a cybernetic warrior with subtle glowing neon circuit markings under translucent porcelain skin. Wet rain reflections on midnight streets, vibrant magenta and cyan anamorphic bokeh, hyper-detailed mechanical eye lens with intricate optical aperture, ultra-photorealistic skin texture, dramatic studio rim lighting, 8k resolution.',
      negativePrompt:
          'blurry, low quality, oversaturated plastic skin, distorted anatomy, extra fingers, cartoon, 3d render',
      aspectRatio: '9:16',
      steps: 28,
      cfgScale: 3.5,
      strength: 0.75,
      gradientColors: [Color(0xFF0F172A), Color(0xFF311042), Color(0xFFD946EF), Color(0xFF38BDF8)],
      tags: ['FLUX.1', 'Cyberpunk', '8K Portrait', 'Cinematic'],
      description: 'Futuristic character portrait with intricate mechanical eye and neon rim light reflections.',
    ),
    ImageTemplate(
      id: 'luxury_product_watch',
      title: 'Luxury Emerald Chronograph Turntable',
      category: 'Product & Commercial',
      model: 'Z-Image Turbo',
      prompt:
          'Commercial studio hero product shot of an ultra-luxury brushed titanium watch with emerald sunburst dial resting on dark matte basalt stone. Precision polished bezel catching soft diffused ring lighting, micro water droplets glistening on sapphire crystal, shallow depth of field, minimalist luxury advertising aesthetic.',
      negativePrompt:
          'scratched glass, dust, deformed hands, cheap plastic, flat lighting, watermark',
      aspectRatio: '1:1',
      steps: 8,
      cfgScale: 2.5,
      strength: 0.70,
      gradientColors: [Color(0xFF18181B), Color(0xFF27272A), Color(0xFF10B981), Color(0xFF059669)],
      tags: ['Commercial', 'Product', 'Turbo 8-Step', 'Basalt'],
      description: 'Ultra-clean commercial studio still life for luxury jewelry, watches, and tech accessories.',
    ),
    ImageTemplate(
      id: 'ethereal_anime_floating_islands',
      title: 'Ethereal Anime Floating Islands',
      category: 'Anime & Fantasy',
      model: 'FLUX.1 Kontext [dev]',
      prompt:
          'Breathtaking Studio Ghibli and Makoto Shinkai inspired landscape of ancient moss-covered floating islands suspended in a golden sunset cloudscape. Cascading crystal waterfalls spilling into mist below, a solitary traveler with wind-blown scarf standing on a cliff edge, flock of migrating white birds, radiant crepuscular rays, painterly masterpiece.',
      negativePrompt:
          'muddy colors, harsh 3d render, modern artifacts, pixelation, low resolution',
      aspectRatio: '16:9',
      steps: 25,
      cfgScale: 4.0,
      strength: 0.75,
      gradientColors: [Color(0xFF1E1B4B), Color(0xFF4C1D95), Color(0xFFF59E0B), Color(0xFFEC4899)],
      tags: ['Anime Style', 'Fantasy Landscape', 'Ghibli Aesthetic', 'Volumetric Sun'],
      description: 'Dreamy floating island scenery with cascading waterfalls and radiant sunset cloud banks.',
    ),
    ImageTemplate(
      id: 'haute_couture_silk_gown',
      title: 'Haute Couture Liquid Silk Gown',
      category: 'Fashion & Try-On',
      model: 'FASHN VTON 1.5',
      prompt:
          'Editorial haute couture fashion photography of a model wearing an avant-garde liquid chrome silk gown with pleated dramatic shoulder silhouettes. Grand Palais Paris marble hall setting, soft diffused afternoon skylight, natural fabric drape physics, high-fashion Vogue cover aesthetic, crisp fabric weave definition.',
      negativePrompt:
          'wrinkled fabric, unnatural seams, warped torso, blurry model, distorted fingers',
      aspectRatio: '9:16',
      steps: 25,
      cfgScale: 4.5,
      strength: 0.75,
      gradientColors: [Color(0xFF172554), Color(0xFF1E40AF), Color(0xFF93C5FD), Color(0xFFDBEAFE)],
      tags: ['Fashion', 'Virtual Try-On', 'Silk Gown', 'Editorial'],
      description: 'Vogue editorial fashion photography ideal for outfit testing and virtual try-on swapping.',
    ),
    ImageTemplate(
      id: 'nordic_glass_villa',
      title: 'Nordic Glass Villa in Snowy Pine Forest',
      category: 'Architecture',
      model: 'FLUX.1 Kontext [dev]',
      prompt:
          'Architectural digest photography of a modern minimalist black timber and floor-to-ceiling glass pavilion secluded in a snow-covered Scandinavian pine forest during blue hour dusk. Warm amber interior lighting radiating through frosted windows, glowing stone fireplace visible inside, pristine fresh snow drifts, cozy Scandinavian architectural design.',
      negativePrompt:
          'deformed structure, crooked lines, unnatural perspective, blurry textures, oversaturated bloom',
      aspectRatio: '16:9',
      steps: 30,
      cfgScale: 3.5,
      strength: 0.75,
      gradientColors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7), Color(0xFFF97316)],
      tags: ['Architecture', 'Blue Hour', 'Minimalist', 'Interior'],
      description: 'Contemporary Scandinavian glass architecture bathed in warm hearth light against arctic snow.',
    ),
    ImageTemplate(
      id: 'macro_bioluminescent_jellyfish',
      title: 'Macro Deep Sea Bioluminescence',
      category: 'Nature & Macro',
      model: 'SDXL Base 1.0',
      prompt:
          'National Geographic underwater macro photography of a translucent crystal jellyfish pulsing in pitch-black deep abyss ocean. Vibrant electric cyan and coral tentacles trailing with delicate filament details, floating bioluminescent plankton particles, refractive caustics, hyper-detailed marine biology.',
      negativePrompt:
          'aquarium glass reflection, noisy background, muddy blur, air bubbles, low contrast',
      aspectRatio: '1:1',
      steps: 32,
      cfgScale: 6.5,
      strength: 0.75,
      gradientColors: [Color(0xFF022C22), Color(0xFF064E3B), Color(0xFF06B6D4), Color(0xFFF43F5E)],
      tags: ['Macro 8K', 'Bioluminescent', 'National Geographic', 'Deep Sea'],
      description: 'Hyper-detailed abyssal sea life with crystalline tentacles and glowing bioluminescence.',
    ),
    ImageTemplate(
      id: 'futuristic_hologram_deck',
      title: 'Futuristic Holographic Command Center',
      category: 'Sci-Fi & 3D',
      model: 'Z-Image Turbo',
      prompt:
          'Isometric sci-fi command deck interior featuring multi-layered translucent turquoise holographic globe displays and planetary telemetry data. Polished dark obsidian flooring with mirror-like reflections, sleek ergonomic console stations, volumetric orange LED strip accents, clean industrial design, Unreal Engine 5 render aesthetic.',
      negativePrompt:
          'cluttered geometry, flat 2d icons, blurry screens, low poly, noisy shadows',
      aspectRatio: '16:9',
      steps: 8,
      cfgScale: 2.0,
      strength: 0.70,
      gradientColors: [Color(0xFF0B0F19), Color(0xFF1E1B4B), Color(0xFF06B6D4), Color(0xFF38BDF8)],
      tags: ['Sci-Fi UI', 'Isometric', 'Turbo', 'Hologram'],
      description: 'High-tech sci-fi dashboard with glowing holographic planetary globes and obsidian floors.',
    ),
    ImageTemplate(
      id: 'vintage_kodachrome_tokyo',
      title: 'Vintage 1970s Kodachrome Tokyo Street',
      category: 'Cinematic Still',
      model: 'FLUX.1 Kontext [dev]',
      prompt:
          'Authentic 1970s 35mm Kodachrome street photography candid capture in Tokyo Shinjuku on a rainy evening. Classic vintage cars with round yellow headlights, pedestrians holding transparent umbrellas beneath glowing retro neon signs, natural film grain, rich analog warmth, nostalgic cinematic Kodachrome color grading.',
      negativePrompt:
          'digital smoothness, overly sharp, modern cars, smartphone, desaturated, plastic',
      aspectRatio: '4:5',
      steps: 28,
      cfgScale: 3.5,
      strength: 0.75,
      gradientColors: [Color(0xFF2E1065), Color(0xFF581C87), Color(0xFFEA580C), Color(0xFFFBBF24)],
      tags: ['35mm Film', 'Kodachrome', 'Retro Tokyo', 'Film Grain'],
      description: 'Nostalgic 1970s 35mm analog street capture with vibrant neon reflections on rain-slicked asphalt.',
    ),
  ];
}
