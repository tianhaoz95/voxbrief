# Branding Assets

This directory contains official branding assets for **Voxbrief**, including social media cards and promotional artwork.

## GitHub Social Media Preview

GitHub repository social preview images customize the open graph (OG) card displayed when sharing the repository on social networks (X/Twitter, LinkedIn, Slack, Discord, iMessage, etc.).

### Specification & Recommended Size
- **Resolution**: 1280 × 640 px (2:1 aspect ratio, exact recommended size)
- **Minimum Requirement**: At least 640 × 320 px
- **Theme**: Light Mode Apple Studio Aesthetic
- **Format**: PNG (< 1 MB)

### Files
| File | Dimensions | Purpose |
| --- | --- | --- |
| [`social-preview.png`](./social-preview.png) | 1280 × 640 px | **Primary asset** for GitHub Repository Settings |
| [`social-preview@2x.png`](./social-preview@2x.png) | 2560 × 1280 px | Ultra high-resolution 2× retina asset |
| [`social_preview.png`](./social_preview.png) | 1280 × 640 px | Naming alias copy |

### How to Upload to GitHub
1. Navigate to the repository on GitHub: [`github.com/tianhaoz95/voxbrief`](https://github.com/tianhaoz95/voxbrief)
2. Go to **Settings** → **General**.
3. Scroll down to the **Social preview** section:
   > *"Upload an image to customize your repository’s social media preview. Images should be at least 640×320px (1280×640px for best display)."*
4. Click **Edit** → **Upload an image...**
5. Select [`branding/social-preview.png`](./social-preview.png).

### How to Regenerate
Run the generator script at any time:
```bash
./scripts/generate_social_preview.py
```
This script reads the live app icon and device screenshots from `metadata/screenshots`, renders the composition with 2× Lanczos super-sampling, and outputs crisp production-ready PNGs.
