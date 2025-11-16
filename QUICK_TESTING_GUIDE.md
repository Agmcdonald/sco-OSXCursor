# Quick Testing Guide - Page Transitions

## How to Test the New Page Transitions Feature

### Step 1: Open the Settings View
1. Launch the app
2. Navigate to the Settings tab/view
3. You should see a "Reader" section with "Page Transition" picker

### Step 2: Test Each Transition Type

#### A. Slide Transition (Default)
1. Select "Slide" from the picker
2. Open any comic in the reader
3. Navigate forward → page should slide from right to left
4. Navigate backward → page should slide from left to right
5. Verify: Smooth, direction-aware motion

#### B. Fade Transition
1. Go back to Settings
2. Select "Fade" from the picker
3. Return to reader
4. Navigate forward/backward → pages should cross-fade
5. Verify: No ghost frames, smooth opacity change

#### C. Zoom Transition
1. Select "Zoom" from Settings
2. Return to reader
3. Navigate forward/backward → pages should zoom in/out with fade
4. Verify: No jitter, smooth scale + opacity

#### D. Page Curl (iOS/iPadOS Only)
1. **iOS devices only:** Select "Page Curl"
2. Return to reader
3. Drag from corner of page to turn
4. Verify: Realistic paper curl, can peek at next page

#### E. None (Instant)
1. Select "None" from Settings
2. Return to reader
3. Navigate → instant page change (no animation)
4. Verify: Super fast, no transition delay

### Step 3: Test in Spread Mode
1. Open a comic in two-page spread mode
2. Try all transitions
3. Verify: All transitions work with spreads

### Step 4: Test Edge Cases

#### Rapid Navigation
1. **macOS:** Rapidly press arrow keys
2. **iOS:** Rapidly swipe pages
3. Verify: No lag, no crashes, smooth transitions

#### Boundary Testing
1. Navigate to first page
2. Try to go backward → should do nothing gracefully
3. Navigate to last page
4. Try to go forward → should do nothing gracefully

#### Settings Persistence
1. Select a transition (e.g., Fade)
2. Close the app completely
3. Reopen the app
4. Verify: Fade transition still selected

### Step 5: Visual Quality Check
1. Zoom into a page (pinch/magnification gesture)
2. Navigate to next page while zoomed
3. Verify: No flicker, clean black background
4. Verify: No ghost frames or visual artifacts

### Expected Results

✅ **Slide:** Pages slide horizontally in correct direction
✅ **Fade:** Pages cross-fade smoothly
✅ **Zoom:** Pages zoom with opacity change
✅ **Curl (iOS):** Native page curl animation
✅ **None:** Instant page changes

### Platform Differences

#### macOS
- Transitions are 0.25s (slightly faster)
- Page Curl is NOT available
- Arrow key navigation works great

#### iOS/iPadOS
- Transitions are 0.3s
- Page Curl IS available
- Swipe gestures work great
- Can drag page corner for curl

### Performance Targets
- No lag during rapid navigation
- Smooth 60fps animations
- No memory leaks
- Works with 100+ page comics

### Troubleshooting

**Problem:** Transition doesn't change after selecting in Settings
- **Solution:** Make sure you returned to the reader view (settings auto-save)

**Problem:** Page Curl not appearing on iOS
- **Solution:** This is normal - check if you're running on iOS/iPadOS (not macOS)

**Problem:** Transitions feel slow
- **Solution:** Try "None" for instant changes, or this is expected behavior

**Problem:** Ghost frames during animation
- **Solution:** This should not happen - report as bug

---

## Quick Status Check

After testing, verify:
- [ ] All 5 transitions work in single-page mode
- [ ] All transitions work in spread mode
- [ ] Settings persist after app restart
- [ ] No crashes at page boundaries
- [ ] No visual artifacts
- [ ] Smooth performance with large comics
- [ ] Platform differences work as expected

If all checked ✅, the implementation is production-ready!

