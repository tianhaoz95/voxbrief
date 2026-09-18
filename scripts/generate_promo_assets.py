#!/usr/bin/env python3
"""
Generates high-resolution promotional graphics and device mockups for Voxbrief
using Pillow. Combines raw screenshots, Apple device bezels, drop shadows,
gradients, typography, and feature callouts.

Outputs:
  metadata/promotional/
  docs/assets/promo/
"""

import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
IPHONE_DIR = REPO_ROOT / "metadata" / "screenshots" / "iphone"
WATCH_DIR = REPO_ROOT / "metadata" / "screenshots" / "watch"
PROMO_DIR = REPO_ROOT / "metadata" / "promotional"
DOCS_PROMO_DIR = REPO_ROOT / "docs" / "assets" / "promo"

PROMO_DIR.mkdir(parents=True, exist_ok=True)
DOCS_PROMO_DIR.mkdir(parents=True, exist_ok=True)

# Font helper
def get_font(size: int, bold: bool = False):
    font_paths = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for p in font_paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()

def draw_gradient_background(width: int, height: int, top_color, bottom_color):
    """Creates a vertical linear gradient image."""
    base = Image.new("RGBA", (width, height), top_color)
    top_r, top_g, top_b = top_color[:3]
    bot_r, bot_g, bot_b = bottom_color[:3]
    
    gradient = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(gradient)
    for y in range(height):
        t = y / float(height)
        r = int(top_r + (bot_r - top_r) * t)
        g = int(top_g + (bot_g - top_g) * t)
        b = int(top_b + (bot_b - top_b) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
    return gradient

def create_iphone_frame(screenshot: Image.Image, target_height: int = 700) -> Image.Image:
    """Wraps an iPhone screenshot in a sleek titanium device frame with dynamic island."""
    aspect = screenshot.width / screenshot.height
    screen_h = target_height
    screen_w = int(screen_h * aspect)
    resized_screen = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    # Frame dimensions
    bezel_thickness = max(10, int(screen_w * 0.035))
    corner_radius = int(screen_w * 0.12)
    frame_w = screen_w + bezel_thickness * 2
    frame_h = screen_h + bezel_thickness * 2

    # Canvas with padding for drop shadow
    pad = 50
    total_w = frame_w + pad * 2
    total_h = frame_h + pad * 2
    canvas = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))

    # 1. Drop shadow
    shadow_mask = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    shadow_box = [pad + 4, pad + 16, pad + frame_w - 4, pad + frame_h + 16]
    s_draw.rounded_rectangle(shadow_box, radius=corner_radius + 4, fill=(0, 0, 0, 110))
    shadow_blurred = shadow_mask.filter(ImageFilter.GaussianBlur(radius=24))
    canvas.paste(shadow_blurred, (0, 0), shadow_blurred)

    # 2. Outer Titanium Body
    frame_layer = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    f_draw = ImageDraw.Draw(frame_layer)
    body_box = [pad, pad, pad + frame_w, pad + frame_h]
    # Dark titanium border
    f_draw.rounded_rectangle(body_box, radius=corner_radius, fill=(35, 36, 40, 255), outline=(70, 72, 78, 255), width=2)

    # 3. Inner Screen Mask & Screen Paste
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    sm_draw = ImageDraw.Draw(screen_mask)
    sm_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=int(corner_radius * 0.8), fill=255)

    screen_canvas = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 255))
    screen_canvas.paste(resized_screen, (0, 0))
    
    # 4. Dynamic Island on top
    di_w = int(screen_w * 0.28)
    di_h = int(screen_h * 0.032)
    di_x0 = (screen_w - di_w) // 2
    di_y0 = int(screen_h * 0.015)
    sc_draw = ImageDraw.Draw(screen_canvas)
    sc_draw.rounded_rectangle([di_x0, di_y0, di_x0 + di_w, di_y0 + di_h], radius=di_h // 2, fill=(0, 0, 0, 255))

    frame_layer.paste(screen_canvas, (pad + bezel_thickness, pad + bezel_thickness), screen_mask)
    canvas.paste(frame_layer, (0, 0), frame_layer)
    return canvas

def create_watch_frame(screenshot: Image.Image, target_height: int = 420) -> Image.Image:
    """Wraps an Apple Watch screenshot in a sleek dark aluminum watch case."""
    aspect = screenshot.width / screenshot.height
    screen_h = target_height
    screen_w = int(screen_h * aspect)
    resized_screen = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    bezel = max(14, int(screen_w * 0.08))
    corner_radius = int(screen_w * 0.26)
    frame_w = screen_w + bezel * 2
    frame_h = screen_h + bezel * 2

    pad = 40
    total_w = frame_w + pad * 2
    total_h = frame_h + pad * 2
    canvas = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))

    # Drop shadow
    shadow_mask = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    s_draw.rounded_rectangle([pad + 4, pad + 12, pad + frame_w - 4, pad + frame_h + 12], radius=corner_radius + 4, fill=(0, 0, 0, 130))
    shadow_blurred = shadow_mask.filter(ImageFilter.GaussianBlur(radius=18))
    canvas.paste(shadow_blurred, (0, 0), shadow_blurred)

    # Watch Case
    case_layer = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(case_layer)
    case_box = [pad, pad, pad + frame_w, pad + frame_h]
    c_draw.rounded_rectangle(case_box, radius=corner_radius, fill=(28, 29, 32, 255), outline=(60, 62, 68, 255), width=2)

    # Digital crown on right
    crown_w = 8
    crown_h = int(frame_h * 0.22)
    crown_x = pad + frame_w - 1
    crown_y = pad + int(frame_h * 0.26)
    c_draw.rounded_rectangle([crown_x, crown_y, crown_x + crown_w, crown_y + crown_h], radius=4, fill=(75, 77, 85, 255))

    # Screen mask
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    sm_draw = ImageDraw.Draw(screen_mask)
    sm_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=int(corner_radius * 0.75), fill=255)

    case_layer.paste(resized_screen, (pad + bezel, pad + bezel), screen_mask)
    canvas.paste(case_layer, (0, 0), case_layer)
    return canvas

def build_promo_hero(iphone_shot_path: Path, watch_shot_path: Path, out_path: Path):
    """Builds the main hero promotional showcase combining Apple Watch & iPhone."""
    canvas_w, canvas_h = 1600, 1000
    img = draw_gradient_background(canvas_w, canvas_h, (13, 17, 23), (22, 27, 34))
    draw = ImageDraw.Draw(img)

    # Decorative glow rings
    glow = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow)
    g_draw.ellipse([800, 200, 1500, 900], fill=(0, 122, 255, 30))
    g_draw.ellipse([200, 400, 800, 1000], fill=(88, 86, 214, 25))
    glow_blurred = glow.filter(ImageFilter.GaussianBlur(radius=80))
    img.paste(glow_blurred, (0, 0), glow_blurred)

    # Typography / Brand Header
    font_badge = get_font(18, bold=True)
    font_title = get_font(48, bold=True)
    font_subtitle = get_font(22)

    # Pill badge
    badge_text = "NATIVE ON-DEVICE AI · IOS 17 & WATCHOS 10"
    badge_bbox = font_badge.getbbox(badge_text)
    badge_w = badge_bbox[2] - badge_bbox[0] + 32
    badge_h = 36
    draw.rounded_rectangle([80, 80, 80 + badge_w, 80 + badge_h], radius=18, fill=(30, 41, 59, 230), outline=(56, 189, 248, 120), width=1)
    draw.text((96, 88), badge_text, font=font_badge, fill=(56, 189, 248, 255))

    # Main Title
    draw.text((80, 136), "Spoken Thoughts to Structured Specs", font=font_title, fill=(255, 255, 255, 255))
    draw.text((80, 200), "Capture on Apple Watch in 1 tap. Sync seamlessly to iPhone.\nTranscribe with Whisper CoreML & format with Qwen3 LLM — 100% offline.", font=font_subtitle, fill=(160, 170, 190, 255))

    # Load and place devices
    if iphone_shot_path.exists():
        iphone_img = Image.open(iphone_shot_path).convert("RGBA")
        iphone_framed = create_iphone_frame(iphone_img, target_height=680)
        # Place iPhone on right side
        img.paste(iphone_framed, (980, 240), iphone_framed)

    if watch_shot_path.exists():
        watch_img = Image.open(watch_shot_path).convert("RGBA")
        watch_framed = create_watch_frame(watch_img, target_height=420)
        # Place Apple Watch overlapping iPhone on left
        img.paste(watch_framed, (680, 440), watch_framed)

    # Feature checklist pills on the left side
    features = [
        ("01", "Instant 1-Tap Watch Capture", "Complications, Smart Stack Live Activity, zero battery drain"),
        ("02", "Stage 1: Whisper ASR", "Verbatim speech-to-text running locally on Neural Engine"),
        ("03", "Stage 2: Qwen3 On-Device LLM", "Formats requirements into bullets and workflow into numbered steps"),
        ("04", "100% Private & Offline", "No accounts, no cloud servers, no telemetry, no subscription"),
    ]
    y_pos = 320
    for num, title, desc in features:
        draw.rounded_rectangle([80, y_pos, 600, y_pos + 68], radius=14, fill=(26, 32, 44, 200), outline=(45, 55, 72, 200), width=1)
        # badge circle
        draw.ellipse([96, y_pos + 16, 132, y_pos + 52], fill=(59, 130, 246, 220))
        num_font = get_font(14, bold=True)
        draw.text((106, y_pos + 25), num, font=num_font, fill=(255, 255, 255))

        f_title_font = get_font(19, bold=True)
        f_desc_font = get_font(13)
        draw.text((144, y_pos + 12), title, font=f_title_font, fill=(255, 255, 255, 255))
        draw.text((144, y_pos + 38), desc, font=f_desc_font, fill=(156, 163, 175, 255))
        y_pos += 88

    img.save(out_path, "PNG")
    print(f"  Generated: {out_path.name}")

def build_promo_pipeline(raw_shot_path: Path, cleaned_shot_path: Path, out_path: Path):
    """Builds the 2-stage processing pipeline comparison banner."""
    canvas_w, canvas_h = 1600, 1000
    img = draw_gradient_background(canvas_w, canvas_h, (15, 23, 42), (2, 6, 23))
    draw = ImageDraw.Draw(img)

    font_title = get_font(44, bold=True)
    font_subtitle = get_font(20)

    draw.text((80, 60), "Two-Stage On-Device AI Pipeline", font=font_title, fill=(255, 255, 255))
    draw.text((80, 120), "How raw spoken voice is transformed into polished engineering specs and action items entirely on your device.", font=font_subtitle, fill=(148, 163, 184))

    # Stage 1 Card (Left)
    if raw_shot_path.exists():
        raw_img = Image.open(raw_shot_path).convert("RGBA")
        raw_framed = create_iphone_frame(raw_img, target_height=650)
        img.paste(raw_framed, (80, 220), raw_framed)

        # Stage 1 badge
        draw.rounded_rectangle([140, 180, 480, 220], radius=10, fill=(30, 58, 138, 220), outline=(59, 130, 246, 255), width=1)
        draw.text((156, 190), "STAGE 1 · WHISPER ASR (VERBATIM)", font=get_font(16, bold=True), fill=(147, 197, 253))

    # Vector Arrow in middle
    arrow_box = [750, 500, 830, 560]
    draw.rounded_rectangle(arrow_box, radius=20, fill=(30, 58, 138, 220), outline=(59, 130, 246, 255), width=2)
    draw.line([(772, 530), (802, 530)], fill=(255, 255, 255), width=4)
    draw.polygon([(802, 520), (816, 530), (802, 540)], fill=(255, 255, 255))

    # Stage 2 Card (Right)
    if cleaned_shot_path.exists():
        cleaned_img = Image.open(cleaned_shot_path).convert("RGBA")
        cleaned_framed = create_iphone_frame(cleaned_img, target_height=650)
        img.paste(cleaned_framed, (880, 220), cleaned_framed)

        # Stage 2 badge
        draw.rounded_rectangle([940, 180, 1320, 220], radius=10, fill=(88, 28, 135, 220), outline=(168, 85, 247, 255), width=1)
        draw.text((956, 190), "STAGE 2 · QWEN3 LLM (STRUCTURED SPEC)", font=get_font(16, bold=True), fill=(216, 180, 254))

    img.save(out_path, "PNG")
    print(f"  Generated: {out_path.name}")

def build_promo_watch(capture_shot: Path, active_shot: Path, queue_shot: Path, out_path: Path):
    """Builds Apple Watch trio showcase."""
    canvas_w, canvas_h = 1600, 900
    img = draw_gradient_background(canvas_w, canvas_h, (17, 24, 39), (3, 7, 18))
    draw = ImageDraw.Draw(img)

    draw.text((80, 60), "Apple Watch Companion: Frictionless Capture", font=get_font(44, bold=True), fill=(255, 255, 255))
    draw.text((80, 120), "Never lose a thought. Instant 1-tap recording from watch complications and Smart Stack with zero delay.", font=get_font(20), fill=(156, 163, 175))

    shots = [
        (capture_shot, "1. Quick Capture", 100),
        (active_shot, "2. Live Waveform & Timer", 600),
        (queue_shot, "3. Offline Notes Queue", 1100),
    ]

    for path, label, x in shots:
        if path.exists():
            w_img = Image.open(path).convert("RGBA")
            framed = create_watch_frame(w_img, target_height=480)
            img.paste(framed, (x, 240), framed)
            draw.text((x + 100, 210), label, font=get_font(20, bold=True), fill=(209, 213, 219))

    img.save(out_path, "PNG")
    print(f"  Generated: {out_path.name}")

def main():
    print("-> Generating promotional graphics...")
    iphone_list = IPHONE_DIR / "01_notes_list.png"
    iphone_detail = IPHONE_DIR / "02_note_detail.png"
    iphone_raw = IPHONE_DIR / "03_two_stage_pipeline.png"
    watch_active = WATCH_DIR / "watch_02_recording_active.png"
    watch_capture = WATCH_DIR / "watch_01_instant_capture.png"
    watch_queue = WATCH_DIR / "watch_03_notes_queue.png"

    # Fallbacks if metadata/screenshots was already populated
    if not iphone_detail.exists():
        iphone_detail = REPO_ROOT / "metadata" / "screenshots" / "test_detail_cleaned.png"
    if not watch_active.exists():
        watch_active = REPO_ROOT / "metadata" / "screenshots" / "watch_active_recording.png"
    if not watch_capture.exists():
        watch_capture = REPO_ROOT / "metadata" / "screenshots" / "watch_test_shot.png"

    # 1. Hero Showcase
    hero_out = PROMO_DIR / "promo_hero.png"
    build_promo_hero(iphone_detail, watch_active, hero_out)
    if hero_out.exists():
        import shutil
        shutil.copy(hero_out, DOCS_PROMO_DIR / "promo_hero.png")

    # 2. Pipeline Comparison
    pipeline_out = PROMO_DIR / "promo_pipeline.png"
    build_promo_pipeline(iphone_raw, iphone_detail, pipeline_out)
    if pipeline_out.exists():
        import shutil
        shutil.copy(pipeline_out, DOCS_PROMO_DIR / "promo_pipeline.png")

    # 3. Watch Showcase
    watch_out = PROMO_DIR / "promo_watch.png"
    build_promo_watch(watch_capture, watch_active, watch_queue, watch_out)
    if watch_out.exists():
        import shutil
        shutil.copy(watch_out, DOCS_PROMO_DIR / "promo_watch.png")

    print("✅ Promotional assets generated successfully!")

if __name__ == "__main__":
    main()
