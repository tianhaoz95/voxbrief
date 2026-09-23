#!/usr/bin/env python3
"""
Generates the high-resolution light-themed GitHub Social Media Preview image for Voxbrief.
Meets GitHub's exact specification:
  "Upload an image to customize your repository’s social media preview.
   Images should be at least 640×320px (1280×640px for best display)."

Features:
- Light-themed studio backdrop with subtle ambient glows (Apple blue & indigo)
- Crisp typography & Apple squircle app icon badge
- 2x2 Feature Highlights (Apple Watch capture, WhisperKit ASR, Qwen3 on-device LLM, 100% private)
- Tech stack pills & 4-step pipeline infographic banner
- Realistic Apple Device Mockups:
  - Natural Titanium iPhone showing light-mode Note Detail UI
  - Dark Aluminum Apple Watch showing live voice recording UI
  - Glassmorphic floating callouts (Two-stage AI pipeline & WCSession auto-sync)
- Super-sampled at 2560×1280 and downsampled via Lanczos to 1280×640 for razor-sharp antialiasing

Outputs:
  branding/social-preview.png     (1280×640)
  branding/social-preview@2x.png  (2560×1280)
  branding/social_preview.png     (1280×640)
"""

import argparse
import os
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT_DIR = REPO_ROOT / "branding"
IPHONE_SHOT_PATH = REPO_ROOT / "metadata" / "screenshots" / "iphone" / "02_note_detail.png"
WATCH_SHOT_PATH = REPO_ROOT / "metadata" / "screenshots" / "watch" / "watch_02_recording_active.png"
APP_ICON_PATH = REPO_ROOT / "VoxbriefApp" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"


def get_font(size: int, weight: str = "regular"):
    """Selects the best available font on macOS."""
    font_map = {
        "bold": [
            ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
            ("/System/Library/Fonts/Avenir Next.ttc", 0),
            ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
        ],
        "demibold": [
            ("/System/Library/Fonts/Avenir Next.ttc", 2),
            ("/System/Library/Fonts/HelveticaNeue.ttc", 10),
            ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
        ],
        "medium": [
            ("/System/Library/Fonts/HelveticaNeue.ttc", 10),
            ("/System/Library/Fonts/Avenir Next.ttc", 5),
            ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
        ],
        "regular": [
            ("/System/Library/Fonts/SFNS.ttf", 0),
            ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
            ("/System/Library/Fonts/Supplemental/Arial.ttf", 0),
        ],
        "mono": [
            ("/System/Library/Fonts/SFNSMono.ttf", 0),
            ("/System/Library/Fonts/Menlo.ttc", 0),
        ],
        "emoji": [
            ("/System/Library/Fonts/Apple Color Emoji.ttc", 0),
        ],
    }

    candidates = font_map.get(weight, font_map["regular"])
    for path, idx in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=idx)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_light_background(w: int, h: int) -> Image.Image:
    """Creates an Apple-style light studio background with subtle ambient glows and tech grid."""
    bg = Image.new("RGBA", (w, h), (248, 250, 252, 255))
    draw = ImageDraw.Draw(bg)

    top_color = (252, 253, 255)
    bot_color = (238, 242, 248)
    for y in range(h):
        t = y / float(h)
        r = int(top_color[0] + (bot_color[0] - top_color[0]) * t)
        g = int(top_color[1] + (bot_color[1] - top_color[1]) * t)
        b = int(top_color[2] + (bot_color[2] - top_color[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))

    glow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow_layer)

    # Ambient color glows
    g_draw.ellipse([1400, 40, 2580, 1220], fill=(0, 122, 255, 34))
    g_draw.ellipse([1150, 480, 2200, 1300], fill=(99, 102, 241, 28))
    g_draw.ellipse([10, -160, 960, 640], fill=(56, 189, 248, 24))

    glow_blurred = glow_layer.filter(ImageFilter.GaussianBlur(radius=140))
    bg.alpha_composite(glow_blurred)

    # Subtle tech dot grid
    grid_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid_layer)
    spacing = 44
    for x in range(22, w, spacing):
        for y in range(22, h, spacing):
            grid_draw.ellipse([x, y, x + 2, y + 2], fill=(148, 163, 184, 38))
    bg.alpha_composite(grid_layer)

    # Top accent gradient bar: cyan -> blue -> purple
    top_bar = Image.new("RGBA", (w, 8), (0, 0, 0, 0))
    tb_draw = ImageDraw.Draw(top_bar)
    for x in range(w):
        t = x / float(w)
        if t < 0.5:
            t2 = t / 0.5
            r = int(56 + (59 - 56) * t2)
            g = int(189 + (130 - 189) * t2)
            b = int(248 + (246 - 248) * t2)
        else:
            t2 = (t - 0.5) / 0.5
            r = int(59 + (168 - 59) * t2)
            g = int(130 + (85 - 130) * t2)
            b = int(246 + (247 - 246) * t2)
        tb_draw.line([(x, 0), (x, 7)], fill=(r, g, b, 255))
    bg.paste(top_bar, (0, 0), top_bar)

    return bg


def create_app_icon_badge(icon_path: Path, target_size: int = 144):
    """Renders the app icon inside an Apple squircle with layered drop shadow and blue glow."""
    raw = Image.open(icon_path).convert("RGBA")
    raw = raw.resize((target_size, target_size), Image.Resampling.LANCZOS)

    pad = 36
    total = target_size + pad * 2
    canvas = Image.new("RGBA", (total, total), (0, 0, 0, 0))

    corner_rad = int(target_size * 0.225)
    mask = Image.new("L", (target_size, target_size), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, target_size, target_size], radius=corner_rad, fill=255)

    # Ambient drop shadow
    s_mask = Image.new("RGBA", (total, total), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(s_mask)
    s_draw.rounded_rectangle([pad, pad + 10, pad + target_size, pad + target_size + 10], radius=corner_rad, fill=(0, 0, 0, 45))
    canvas.alpha_composite(s_mask.filter(ImageFilter.GaussianBlur(radius=16)))

    # Blue tint glow
    s_mask2 = Image.new("RGBA", (total, total), (0, 0, 0, 0))
    s2_draw = ImageDraw.Draw(s_mask2)
    s2_draw.rounded_rectangle([pad, pad + 12, pad + target_size, pad + target_size + 12], radius=corner_rad, fill=(37, 99, 235, 55))
    canvas.alpha_composite(s_mask2.filter(ImageFilter.GaussianBlur(radius=22)))

    # App icon
    icon_layer = Image.new("RGBA", (total, total), (0, 0, 0, 0))
    icon_layer.paste(raw, (pad, pad), mask)

    # Edge highlight borders
    b_draw = ImageDraw.Draw(icon_layer)
    b_draw.rounded_rectangle([pad, pad, pad + target_size, pad + target_size], radius=corner_rad, outline=(255, 255, 255, 180), width=2)
    b_draw.rounded_rectangle([pad - 1, pad - 1, pad + target_size + 1, pad + target_size + 1], radius=corner_rad + 1, outline=(0, 0, 0, 25), width=1)

    canvas.alpha_composite(icon_layer)
    return canvas, pad


def create_iphone_light_mockup(screenshot_path: Path, target_height: int = 1080):
    """Wraps an iPhone screenshot in a natural titanium device frame with dynamic island and shadow."""
    raw = Image.open(screenshot_path).convert("RGBA")
    aspect = raw.width / raw.height
    screen_h = target_height
    screen_w = int(screen_h * aspect)
    screen = raw.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    bezel = max(16, int(screen_w * 0.036))
    corner_radius = int(screen_w * 0.125)
    frame_w = screen_w + bezel * 2
    frame_h = screen_h + bezel * 2

    pad = 80
    canvas_w = frame_w + pad * 2
    canvas_h = frame_h + pad * 2
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    # Multi-layer drop shadows
    sh1 = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sh1_draw = ImageDraw.Draw(sh1)
    sh1_draw.rounded_rectangle([pad + 8, pad + 36, pad + frame_w - 8, pad + frame_h + 36], radius=corner_radius + 6, fill=(15, 23, 42, 45))
    canvas.alpha_composite(sh1.filter(ImageFilter.GaussianBlur(radius=42)))

    sh2 = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sh2_draw = ImageDraw.Draw(sh2)
    sh2_draw.rounded_rectangle([pad + 3, pad + 16, pad + frame_w - 3, pad + frame_h + 16], radius=corner_radius + 2, fill=(15, 23, 42, 60))
    canvas.alpha_composite(sh2.filter(ImageFilter.GaussianBlur(radius=18)))

    # Natural Titanium body
    frame = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    f_draw = ImageDraw.Draw(frame)
    frame_box = [pad, pad, pad + frame_w, pad + frame_h]
    f_draw.rounded_rectangle(frame_box, radius=corner_radius, fill=(226, 232, 240, 255), outline=(203, 213, 225, 255), width=2)

    # Dark inner bezel
    inner_box = [pad + 2, pad + 2, pad + frame_w - 2, pad + frame_h - 2]
    f_draw.rounded_rectangle(inner_box, radius=corner_radius - 2, fill=(26, 28, 32, 255))

    # Screen mask & paste
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    sm_draw = ImageDraw.Draw(screen_mask)
    screen_radius = int(corner_radius * 0.82)
    sm_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_radius, fill=255)

    screen_canvas = Image.new("RGBA", (screen_w, screen_h), (255, 255, 255, 255))
    screen_canvas.paste(screen, (0, 0))

    # Dynamic Island pill
    di_w = int(screen_w * 0.28)
    di_h = int(screen_h * 0.034)
    di_x = (screen_w - di_w) // 2
    di_y = int(screen_h * 0.016)
    sc_draw = ImageDraw.Draw(screen_canvas)
    sc_draw.rounded_rectangle([di_x, di_y, di_x + di_w, di_y + di_h], radius=di_h // 2, fill=(0, 0, 0, 255))

    frame.paste(screen_canvas, (pad + bezel, pad + bezel), screen_mask)
    canvas.alpha_composite(frame)
    return canvas, pad, frame_w, frame_h


def create_watch_mockup(screenshot_path: Path, target_height: int = 500):
    """Wraps an Apple Watch screenshot in a dark aluminum watch case with crown ridges and shadow."""
    raw = Image.open(screenshot_path).convert("RGBA")
    aspect = raw.width / raw.height
    screen_h = target_height
    screen_w = int(screen_h * aspect)
    screen = raw.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    bezel = max(18, int(screen_w * 0.09))
    corner_radius = int(screen_w * 0.26)
    frame_w = screen_w + bezel * 2
    frame_h = screen_h + bezel * 2

    pad = 60
    canvas_w = frame_w + pad * 2
    canvas_h = frame_h + pad * 2
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    # Drop shadows
    sh = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sh)
    sh_draw.rounded_rectangle([pad + 4, pad + 24, pad + frame_w - 4, pad + frame_h + 24], radius=corner_radius + 4, fill=(15, 23, 42, 65))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(radius=28)))

    sh2 = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sh2_draw = ImageDraw.Draw(sh2)
    sh2_draw.rounded_rectangle([pad + 2, pad + 10, pad + frame_w - 2, pad + frame_h + 10], radius=corner_radius + 2, fill=(15, 23, 42, 80))
    canvas.alpha_composite(sh2.filter(ImageFilter.GaussianBlur(radius=14)))

    case = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(case)

    # Digital Crown (right side)
    crown_w = 12
    crown_h = int(frame_h * 0.24)
    crown_x = pad + frame_w
    crown_y = pad + int(frame_h * 0.22)
    c_draw.rounded_rectangle([crown_x, crown_y, crown_x + crown_w, crown_y + crown_h], radius=4, fill=(55, 65, 81, 255), outline=(75, 85, 99, 255), width=1)
    for ry in range(crown_y + 4, crown_y + crown_h - 4, 6):
        c_draw.line([(crown_x + 2, ry), (crown_x + crown_w - 2, ry)], fill=(31, 41, 55, 255), width=1)

    # Side button
    btn_w = 6
    btn_h = int(frame_h * 0.18)
    btn_x = pad + frame_w
    btn_y = pad + int(frame_h * 0.56)
    c_draw.rounded_rectangle([btn_x, btn_y, btn_x + btn_w, btn_y + btn_h], radius=3, fill=(55, 65, 81, 255))

    # Case body
    case_box = [pad, pad, pad + frame_w, pad + frame_h]
    c_draw.rounded_rectangle(case_box, radius=corner_radius, fill=(24, 25, 29, 255), outline=(75, 85, 99, 255), width=2)

    # Screen
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    sm_draw = ImageDraw.Draw(screen_mask)
    sm_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=int(corner_radius * 0.78), fill=255)

    case.paste(screen, (pad + bezel, pad + bezel), screen_mask)
    canvas.alpha_composite(case)
    return canvas, pad, frame_w, frame_h


def draw_pill(draw: ImageDraw.ImageDraw, box, bg_color, border_color, radius: int, width: int = 1):
    draw.rounded_rectangle(box, radius=radius, fill=bg_color, outline=border_color, width=width)


def draw_feature_card(draw: ImageDraw.ImageDraw, box, emoji: str, title: str, subtitle: str, f_title, f_sub, f_emoji, bg_icon_color):
    x0, y0, x1, y1 = box
    h = y1 - y0
    card_radius = 22

    draw.rounded_rectangle(box, radius=card_radius, fill=(255, 255, 255, 240), outline=(226, 232, 240, 255), width=2)

    circle_size = 68
    cx0 = x0 + 20
    cy0 = y0 + (h - circle_size) // 2
    cx1 = cx0 + circle_size
    cy1 = cy0 + circle_size
    draw.ellipse([cx0, cy0, cx1, cy1], fill=bg_icon_color)

    e_bbox = f_emoji.getbbox(emoji)
    ew = e_bbox[2] - e_bbox[0]
    eh = e_bbox[3] - e_bbox[1]
    draw.text((cx0 + (circle_size - ew) // 2 - e_bbox[0], cy0 + (circle_size - eh) // 2 - e_bbox[1]), emoji, font=f_emoji, embedded_color=True)

    tx = cx1 + 20
    ty_title = y0 + 24
    ty_sub = ty_title + 36
    draw.text((tx, ty_title), title, font=f_title, fill=(15, 23, 42, 255))
    draw.text((tx, ty_sub), subtitle, font=f_sub, fill=(100, 116, 139, 255))


def draw_arrow_connector(draw: ImageDraw.ImageDraw, start_x: int, y: int, length: int = 32, color=(148, 163, 184, 255)):
    end_x = start_x + length
    draw.line([(start_x, y), (end_x, y)], fill=color, width=3)
    draw.polygon([(end_x, y - 5), (end_x + 7, y), (end_x, y + 5)], fill=color)


def generate_social_preview(output_dir: Path):
    """Generates the 2x (2560x1280) and 1x (1280x640) social preview images."""
    output_dir.mkdir(parents=True, exist_ok=True)

    canvas_w = 2560
    canvas_h = 1280

    print("🎨 Generating Light-Themed GitHub Social Preview...")
    print("   Canvas Size: 2560×1280 (Super-sampled 2x)")
    print("   Target Output: 1280×640 (2:1 Aspect Ratio)")

    # 1. Background
    img = draw_light_background(canvas_w, canvas_h)
    draw = ImageDraw.Draw(img)

    # Fonts
    f_badge = get_font(22, "bold")
    f_title = get_font(86, "bold")
    f_subtitle = get_font(40, "demibold")
    f_body = get_font(27, "regular")
    f_card_title = get_font(25, "bold")
    f_card_sub = get_font(18, "medium")
    f_pill = get_font(20, "medium")
    f_emoji = get_font(40, "emoji")
    f_step_num = get_font(18, "bold")
    f_step_title = get_font(20, "bold")
    f_footer = get_font(24, "demibold")

    # 2. App Icon & Title
    icon_img, icon_pad = create_app_icon_badge(APP_ICON_PATH, target_size=144)
    icon_x = 100
    icon_y = 90
    img.alpha_composite(icon_img, (icon_x - icon_pad, icon_y - icon_pad))

    badge_x0 = 275
    badge_y0 = 96
    badge_text = "OPEN SOURCE · iOS 17+ · watchOS 10+"
    b_bbox = f_badge.getbbox(badge_text)
    bw = b_bbox[2] - b_bbox[0]
    bh = b_bbox[3] - b_bbox[1]
    draw_pill(draw, [badge_x0, badge_y0, badge_x0 + bw + 28, badge_y0 + bh + 16], (239, 246, 255, 255), (191, 219, 254, 255), radius=(bh + 16) // 2, width=2)
    draw.text((badge_x0 + 14, badge_y0 + 7), badge_text, font=f_badge, fill=(29, 78, 216, 255))

    title_text = "Voxbrief"
    draw.text((badge_x0, 146), title_text, font=f_title, fill=(15, 23, 42, 255))

    # 3. Subtitle & Description
    sub_text = "Voice Idea Capture & On-Device AI Cleanup"
    draw.text((100, 268), sub_text, font=f_subtitle, fill=(30, 41, 59, 255))

    desc_lines = [
        "Capture fleeting thoughts effortlessly on Apple Watch and iPhone.",
        "Transcribed by Whisper and refined into structured Markdown notes",
        "by Qwen3 LLM — running 100% on-device, private and offline.",
    ]
    dy = 332
    for line in desc_lines:
        draw.text((100, dy), line, font=f_body, fill=(71, 85, 105, 255))
        dy += 42

    # 4. 2x2 Feature Highlights
    cards = [
        ([100, 485, 675, 605], "⌚", "Apple Watch Capture", "1-tap complications & Smart Stack Live Activity", (239, 246, 255, 255)),
        ([705, 485, 1280, 605], "⚡", "WhisperKit Speech-to-Text", "On-device Whisper base.en transcription", (255, 251, 235, 255)),
        ([100, 630, 675, 750], "🧠", "Qwen3 On-Device LLM", "Structured Markdown, requirements & action items", (250, 245, 255, 255)),
        ([705, 630, 1280, 750], "🔒", "100% Private & Local", "CoreML & Metal acceleration · Zero cloud", (236, 253, 245, 255)),
    ]
    for box, emoji, c_title, c_sub, bg_c in cards:
        draw_feature_card(draw, box, emoji, c_title, c_sub, f_card_title, f_card_sub, f_emoji, bg_c)

    # 5. Tech Stack Pills
    pills = ["SwiftUI", "Apple WatchOS", "WhisperKit", "MLX Swift (Qwen3)", "WidgetKit", "CoreML / Metal"]
    px = 100
    py = 785
    for p_text in pills:
        pb = f_pill.getbbox(p_text)
        pw = pb[2] - pb[0]
        ph = pb[3] - pb[1]
        draw_pill(draw, [px, py, px + pw + 28, py + ph + 18], (255, 255, 255, 230), (203, 213, 225, 255), radius=(ph + 18) // 2, width=2)
        draw.text((px + 14, py + 8), p_text, font=f_pill, fill=(51, 65, 85, 255))
        px += pw + 38

    # 6. Pipeline Infographic Banner
    pipe_y = 875
    pipe_box = [100, pipe_y, 1280, pipe_y + 96]
    draw.rounded_rectangle(pipe_box, radius=20, fill=(255, 255, 255, 245), outline=(226, 232, 240, 255), width=2)

    step_data = [
        ("1", "Watch Capture", (2, 132, 199), (224, 242, 254)),
        ("2", "Whisper ASR", (217, 119, 6), (254, 243, 199)),
        ("3", "Qwen3 LLM", (147, 51, 234), (243, 232, 255)),
        ("4", "Clean Note", (22, 163, 74), (220, 252, 231)),
    ]
    cur_x = 125
    for i, (num, label, color, bg_c) in enumerate(step_data):
        num_b = f_step_num.getbbox(num)
        nw = num_b[2] - num_b[0]
        nh = num_b[3] - num_b[1]
        circle_r = 16
        circle_cx = cur_x + circle_r
        circle_cy = pipe_y + 48
        draw.ellipse([circle_cx - circle_r, circle_cy - circle_r, circle_cx + circle_r, circle_cy + circle_r], fill=bg_c, outline=color, width=2)
        draw.text((circle_cx - nw // 2 - num_b[0], circle_cy - nh // 2 - num_b[1]), num, font=f_step_num, fill=color)

        cur_x += circle_r * 2 + 12
        draw.text((cur_x, pipe_y + 36), label, font=f_step_title, fill=(30, 41, 59, 255))
        lb = f_step_title.getbbox(label)
        cur_x += (lb[2] - lb[0]) + 16

        if i < len(step_data) - 1:
            draw_arrow_connector(draw, cur_x, pipe_y + 48, length=30, color=(148, 163, 184, 255))
            cur_x += 46

    # 7. Footer Info Card
    foot_y = 1010
    foot_box = [100, foot_y, 1280, foot_y + 80]
    draw.rounded_rectangle(foot_box, radius=18, fill=(241, 245, 249, 180), outline=(226, 232, 240, 255), width=2)
    draw.text((130, foot_y + 24), "github.com/tianhaoz95/voxbrief", font=f_footer, fill=(29, 78, 216, 255))
    draw.text((540, foot_y + 24), "·  Native Swift · CoreML & Metal · No Backend", font=f_footer, fill=(71, 85, 105, 255))

    # 8. Device Mockups
    iphone_img, ip_pad, ip_w, ip_h = create_iphone_light_mockup(IPHONE_SHOT_PATH, target_height=1080)
    watch_img, w_pad, w_w, w_h = create_watch_mockup(WATCH_SHOT_PATH, target_height=500)

    # Position iPhone (X=1910, Y=90)
    iphone_x = 1910 - ip_pad
    iphone_y = 90 - ip_pad
    img.alpha_composite(iphone_img, (iphone_x, iphone_y))

    # Position Watch (X=1430, Y=660)
    watch_x = 1430 - w_pad
    watch_y = 660 - w_pad
    img.alpha_composite(watch_img, (watch_x, watch_y))

    # 9. Floating Callout Badges
    # A. Two-Stage AI Pipeline
    fl_x = 1380
    fl_y = 175
    fl_w = 420
    fl_h = 108
    callout_box = [fl_x, fl_y, fl_x + fl_w, fl_y + fl_h]

    co_sh = Image.new("RGBA", (fl_w + 40, fl_h + 40), (0, 0, 0, 0))
    co_sh_draw = ImageDraw.Draw(co_sh)
    co_sh_draw.rounded_rectangle([20, 20, fl_w + 20, fl_h + 20], radius=24, fill=(15, 23, 42, 35))
    img.alpha_composite(co_sh.filter(ImageFilter.GaussianBlur(radius=12)), (fl_x - 20, fl_y - 20))

    draw.rounded_rectangle(callout_box, radius=22, fill=(255, 255, 255, 245), outline=(191, 219, 254, 255), width=2)
    p_cx, p_cy = fl_x + 36, fl_y + 36
    draw.ellipse([p_cx - 14, p_cy - 14, p_cx + 14, p_cy + 14], fill=(219, 234, 254, 255))
    draw.ellipse([p_cx - 8, p_cy - 8, p_cx + 8, p_cy + 8], fill=(37, 99, 235, 255))
    draw.ellipse([p_cx - 3, p_cy - 3, p_cx + 3, p_cy + 3], fill=(255, 255, 255, 255))

    f_fl_title = get_font(23, "bold")
    f_fl_pills = get_font(17, "bold")
    draw.text((fl_x + 60, fl_y + 24), "Two-Stage AI Pipeline", font=f_fl_title, fill=(15, 23, 42, 255))

    p1_box = [fl_x + 24, fl_y + 60, fl_x + 200, fl_y + 92]
    draw_pill(draw, p1_box, (254, 243, 199, 255), (251, 191, 36, 255), radius=16, width=1)
    draw.text((fl_x + 38, fl_y + 67), "1. Whisper ASR", font=f_fl_pills, fill=(180, 83, 9, 255))

    draw_arrow_connector(draw, fl_x + 210, fl_y + 76, length=20, color=(148, 163, 184, 255))

    p2_box = [fl_x + 246, fl_y + 60, fl_x + 396, fl_y + 92]
    draw_pill(draw, p2_box, (243, 232, 255, 255), (192, 132, 252, 255), radius=16, width=1)
    draw.text((fl_x + 260, fl_y + 67), "2. Qwen3 LLM", font=f_fl_pills, fill=(126, 34, 206, 255))

    # B. WCSession Auto-Sync Badge
    ws_x = 1450
    ws_y = 575
    ws_w = 260
    ws_h = 48
    ws_box = [ws_x, ws_y, ws_x + ws_w, ws_y + ws_h]

    ws_sh = Image.new("RGBA", (ws_w + 30, ws_h + 30), (0, 0, 0, 0))
    ws_sh_draw = ImageDraw.Draw(ws_sh)
    ws_sh_draw.rounded_rectangle([15, 15, ws_w + 15, ws_h + 15], radius=24, fill=(15, 23, 42, 30))
    img.alpha_composite(ws_sh.filter(ImageFilter.GaussianBlur(radius=8)), (ws_x - 15, ws_y - 15))

    draw_pill(draw, ws_box, (255, 255, 255, 245), (226, 232, 240, 255), radius=24, width=2)
    draw.ellipse([ws_x + 18, ws_y + 18, ws_x + 30, ws_y + 30], fill=(34, 197, 94, 255))
    f_ws = get_font(18, "bold")
    draw.text((ws_x + 38, ws_y + 14), "WCSession Auto-Sync", font=f_ws, fill=(15, 23, 42, 255))

    # 10. Save Outputs
    out_2x = output_dir / "social-preview@2x.png"
    out_1x = output_dir / "social-preview.png"
    out_alt = output_dir / "social_preview.png"

    print(f"💾 Saving 2x preview: {out_2x} (2560×1280)...")
    img.save(out_2x, "PNG", optimize=True)

    print(f"💾 Downsampling and saving 1x preview: {out_1x} (1280×640)...")
    img_1x = img.resize((1280, 640), Image.Resampling.LANCZOS)
    img_1x.save(out_1x, "PNG", optimize=True)

    # Save copy with underscore convention
    shutil.copyfile(out_1x, out_alt)

    print("✅ Successfully generated social preview images!")
    print(f"   • {out_1x} ({img_1x.width}×{img_1x.height}px, {out_1x.stat().st_size // 1024} KB)")
    print(f"   • {out_2x} ({img.width}×{img.height}px, {out_2x.stat().st_size // 1024} KB)")
    print(f"   • {out_alt} (alias copy)")


def main():
    parser = argparse.ArgumentParser(description="Generate light-themed GitHub social media preview.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT_DIR, help="Output directory for branding assets")
    args = parser.parse_args()
    generate_social_preview(args.output_dir)


if __name__ == "__main__":
    main()
