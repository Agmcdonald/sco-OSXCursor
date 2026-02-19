# Agent Skill: Nano Banana Studio
## Description
This skill specializes in generating visual assets for SCO-OSXCursor using the Nano Banana image model. It ensures all generated graphics—app icons, placeholder covers, and empty state illustrations—adhere to the project's "Vibrant Comic Book" aesthetic.

## Trigger
Use this skill when:
- The user asks to "generate an icon", "make a placeholder", or "create art".
- The user mentions "Nano Banana" or "assets".
- The user needs UI mockups or empty state visuals.

## Rules & Constraints
1. **Aesthetic Consistency:**
   - ALWAYS append the following style modifiers to image prompts: *"comic book style, cel-shaded, vibrant colors, clean lines, digital art, high fidelity"*.
   - Avoid photorealism. The app is a comic reader; the UI art should look like a comic.

2. **App Icon Guidelines (macOS/iOS):**
   - If generating an **App Icon**:
     - Prompt structure: *"A central [Subject] composed of [Elements], 3D render, clay morphism style, vibrant [Color] background, suitable for macOS app icon, rounded square shape"*.
     - Ensure the subject is centered with clear margins.

3. **Placeholder Covers:**
   - If generating **Comic Covers** (for testing the library view):
     - Prompt structure: *"A comic book cover featuring [Subject], dynamic action pose, title text '[Title]' at the top, issue number '#1', vintage halftone dots texture"*.

## Prompt Templates
- **Empty Library State:** *"A lonely superhero sitting on an empty wooden crate, waiting for comics, cel-shaded, soft lighting, melancholy but cute."*
- **Corrupted File Icon:** *"A comic book page tearing in half, glitch art style, digital artifacts, red and black warning colors."*

## Output Instruction
When the user requests an image, do not just describe it. Construct the optimized prompt based on the rules above and immediately call the image generation tool.