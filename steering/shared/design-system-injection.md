---
inclusion: manual
---

# Design System Injection for Workers

When building production UI, every frontend worker MUST receive a design system context that ensures visual consistency across independently-built components.

## The Problem

Workers build components in isolation. Without shared design context:
- Worker A uses `bg-blue-500` for buttons, Worker B uses `bg-indigo-600`
- Worker A uses `p-4` spacing, Worker B uses `p-6`
- Worker A uses 14px font, Worker B uses 16px
- The result: an app that looks like 5 different people built it (because they did)

## The Solution: Design Token File

Before ANY frontend code is written, create a design token file that ALL workers reference. This file is committed to the repo and included in every frontend worker's prompt.

### File: `src/lib/design-tokens.ts` (or equivalent for project's framework)

```typescript
// Generated from sprint contract Design Spec — DO NOT modify without updating contract
export const tokens = {
  colors: {
    // Paste from contract's color palette section
    primary: { ... },
    neutral: { ... },
    semantic: { ... },
  },
  typography: {
    // Paste from contract's typography section
    fontFamily: { ... },
    fontSize: { ... },
    lineHeight: { ... },
  },
  spacing: {
    // Consistent scale
    xs: '4px', sm: '8px', md: '16px', lg: '24px', xl: '32px',
  },
  layout: {
    sidebar: { width: '260px', ... },
    main: { ... },
    panel: { width: '400px', ... },
  },
  animation: {
    fadeIn: '150ms ease-in',
    slideIn: '200ms ease-out',
  },
} as const;
```

### For Tailwind projects: `tailwind.config.ts`

Extend the Tailwind config with the contract's design spec:

```typescript
export default {
  theme: {
    extend: {
      colors: {
        // From contract Design Spec
      },
      fontFamily: {
        // From contract Design Spec
      },
      fontSize: {
        // From contract typography scale
      },
    },
  },
}
```

## Worker Prompt Injection

Every frontend worker's prompt MUST include:

```
## Design System (MANDATORY — deviations are bugs)

This project uses [design system name] with these tokens:
- Primary color: [hex]
- Text sizes: [scale]
- Spacing: [scale]
- Border radius: [value]
- Shadows: [scale]

Use ONLY these values. If you need a color not in the palette, that's a sign you're
doing something wrong. Check the design tokens file at [path].

DO NOT use:
- Inline styles
- Arbitrary color values (not from palette)
- Arbitrary spacing (not from scale)
- Custom fonts (not from config)
- Random border-radius values

Your component will be reviewed against the design system. If it uses values not in
the tokens, it will be rejected.
```

## Cross-Component Consistency

For dense UIs with many interactive components (chat apps, dashboards, project managers):

1. **Build shared components FIRST** (milestone 2, after scaffolding):
   - Button, Input, Avatar, Badge, Tooltip, Dialog, Popover
   - These use the design tokens and become the building blocks

2. **Subsequent workers import shared components:**
   - Worker building "message list" imports shared Avatar, Badge
   - Worker building "sidebar" imports shared Badge, Tooltip
   - They DON'T build their own versions

3. **Include the component inventory in worker prompts:**
   ```
   ## Available Components (import from @/components/ui/)
   - Button: variants={default|destructive|outline|ghost} size={sm|md|lg}
   - Avatar: size={sm|md|lg} status={online|away|offline}
   - Badge: variant={default|secondary|destructive} count={number}
   ...
   
   DO NOT build your own button/avatar/badge. Use these.
   ```

## Enforcement

The spec reviewer for each task MUST check:
1. Does the code import from shared components? (not building ad-hoc UI)
2. Are all color values from the palette? (grep for arbitrary hex values)
3. Are all spacing values from the scale? (grep for arbitrary px values)
4. Does the component match the density/style of existing components?

The design validator at end-of-build captures screenshots and verifies visual consistency across all views.
