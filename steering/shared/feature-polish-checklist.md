---
inclusion: manual
---

# Feature Polish Checklist

When building production features, each feature needs MORE than just "it works." This checklist ensures features feel polished — like they were built by a product team, not a hackathon.

## The Three Passes

Workers should implement features in three passes:

### Pass 1: Core Functionality (what the AC says)
- The feature works as described in the acceptance criterion
- Happy path verified

### Pass 2: States & Edge Cases (what users encounter)
- Empty state: what shows before any data?
- Loading state: skeleton/spinner while fetching
- Error state: what if the API fails? what if WebSocket disconnects?
- Partial state: what if some data loads but not all?
- Overflow: what if there are 100 items? 1000?
- Long content: what if a message is 5000 characters?
- Rapid actions: what if user clicks 10 times fast?

### Pass 3: Polish & Micro-interactions (what makes it feel professional)
- Animation on state change (fade in, slide, bounce)
- Keyboard shortcut (if applicable)
- Tooltip on hover (for icon-only buttons)
- Focus management (after action, where does focus go?)
- Optimistic UI (show result immediately, revert on error)
- Sound/haptic feedback (for key actions like sending a message)
- Undo option (for destructive actions)

## Per-Feature Polish Examples

### Chat Message
**Pass 1:** Message renders in the list
**Pass 2:** Loading skeleton while fetching history, error banner if WebSocket drops, "load more" for scrollback
**Pass 3:** Fade-in animation for new messages, scroll-to-bottom button when not at bottom, "New messages" divider for unread, hover to show timestamp

### Emoji Reaction
**Pass 1:** Click emoji → reaction appears under message
**Pass 2:** Toggle (click again to remove), count display, handle if same emoji from multiple users
**Pass 3:** Reaction animation (pop/scale), hover to show who reacted, skin tone picker, frequently-used section

### Typing Indicator
**Pass 1:** "Alice is typing..." shows when another user types
**Pass 2:** Multiple typers ("Alice and Bob are typing..."), timeout after 5s
**Pass 3:** Three bouncing dots animation, position below message list, smooth appear/disappear transition

### File Upload
**Pass 1:** Drag file → uploads → shows in chat
**Pass 2:** Progress bar, cancel button, file size validation, type validation, error on failure
**Pass 3:** Drag overlay animation, paste from clipboard support, image preview before send, retry on failure

## How Workers Should Use This

Each task prompt should include:

```
## Polish Requirements

This is a production feature. Implement ALL THREE passes:
1. Core: [specific AC from contract]
2. States: loading skeleton, error message, empty state, overflow handling
3. Polish: [specific micro-interactions from this list]

A feature without Pass 2 and Pass 3 will be rejected in review.
```

## Integration with Spec Review

The spec reviewer for each task MUST check:
1. Does the implementation handle the empty state? (look for conditional rendering)
2. Does it have a loading state? (look for isLoading/skeleton)
3. Does it handle errors? (look for try/catch + error UI)
4. Is there any animation/transition? (look for Tailwind transition classes or framer-motion)
5. Is the feature keyboard accessible? (look for onKeyDown handlers or proper button elements)

If any of these are missing, the spec review returns FAIL and the worker must add them.
