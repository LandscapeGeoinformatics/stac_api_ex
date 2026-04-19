# Style Review — lgeo_stac_api_ex

This document summarises the current visual colour palette for designer/reviewer feedback.
All colours come from [Tailwind CSS](https://tailwindcss.com/docs/colors) — you can explore
swatches and alternatives interactively on that page.

---

## Page Background

The main app background is a soft diagonal gradient:

| Role | Tailwind class | Hex |
|---|---|---|
| Left edge | `from-blue-50` | #eff6ff |
| Centre | `via-white` | #ffffff |
| Right edge | `to-green-50` | #f0fdf4 |

Cards and panels sit on `bg-white` (#ffffff) or `bg-gray-50` (#f9fafb).

---

## Buttons & Primary Actions

Two colours share the "primary action" role depending on context — **blue** for generic actions
and **green** for catalog/collection-related actions.

### Blue (generic / API actions)

| State | Tailwind class | Hex | Swatch |
|---|---|---|---|
| Default | `bg-blue-600` | #2563eb | ![#2563eb](https://placehold.co/18x18/2563eb/2563eb.png) |
| Hover | `bg-blue-700` | #1d4ed8 | ![#1d4ed8](https://placehold.co/18x18/1d4ed8/1d4ed8.png) |
| Focus ring | `ring-blue-500` | #3b82f6 | ![#3b82f6](https://placehold.co/18x18/3b82f6/3b82f6.png) |
| Label | `text-white` | #ffffff | |

### Green (catalog / collection actions)

| State | Tailwind class | Hex | Swatch |
|---|---|---|---|
| Default | `bg-green-600` | #16a34a | ![#16a34a](https://placehold.co/18x18/16a34a/16a34a.png) |
| Hover | `bg-green-700` | #15803d | ![#15803d](https://placehold.co/18x18/15803d/15803d.png) |
| Focus ring | `ring-green-500` | #22c55e | ![#22c55e](https://placehold.co/18x18/22c55e/22c55e.png) |
| Label | `text-white` | #ffffff | |

### Neutral / ghost buttons

| State | Tailwind class | Hex |
|---|---|---|
| Default | `bg-gray-600` | #4b5563 |
| Hover (dark) | `bg-gray-800` | #1f2937 |
| Hover (light/ghost) | `bg-gray-50` | #f9fafb |
| Label | `text-white` / `text-gray-700` | #ffffff / #374151 |

> **Feedback opportunity:** Blue and green currently carry equal visual weight as action colours.
> If reviewers feel the dual-primary is confusing, picking one as the dominant CTA colour and
> demoting the other to a secondary/outline style would tighten the hierarchy.

---

## Semantic Badges (entity type chips)

Small inline labels that identify STAC entity types.

| Entity type | Background class | Bg hex | Text class | Text hex |
|---|---|---|---|---|
| Collection | `bg-blue-100` | `#dbeafe` | `text-blue-800` | #1e40af |
| Catalog | `bg-green-100` | `#dcfce7` | `text-green-800` | #166534 |
| Asset / media type | `bg-purple-100` | `#f3e8ff` | `text-purple-800` | #6b21a8 |
| Neutral / other | `bg-gray-100` | `#f3f4f6` | `text-gray-700` | #374151 |
| Warning / notice | `bg-yellow-50` | `#fefce8` | `text-yellow-700` | #a16207 |

---

## Text Hierarchy

| Role | Tailwind class | Hex |
|---|---|---|
| Page / section headings | `text-gray-900` | #111827 |
| Domain headings (green) | `text-green-900` | #14532d |
| Domain headings (blue) | `text-blue-900` | #1e3a8a |
| Body text | `text-gray-700` | #374151 |
| Secondary / caption | `text-gray-600` | #4b5563 |
| Muted / metadata | `text-gray-500` | #6b7280 |
| Placeholder / disabled | `text-gray-400` | #9ca3af |
| Hyperlinks | `text-blue-600` | #2563eb |
| Link hover | `text-blue-700` | #1d4ed8 |

---

## Full Colour Scales in Use

These are the exact shades currently referenced in the codebase.
The Tailwind colour explorer lets you browse the full 50–950 scale for each hue:

| Hue | Tailwind docs link | Shades used |
|---|---|---|
| Gray | [tailwindcss.com/docs/colors](https://tailwindcss.com/docs/colors) | 50, 100, 200, 300, 400, 500, 600, 700, 800, 900 |
| Blue | [tailwindcss.com/docs/colors](https://tailwindcss.com/docs/colors) | 50, 100, 200, 300, 500, 600, 700, 800, 900 |
| Green | [tailwindcss.com/docs/colors](https://tailwindcss.com/docs/colors) | 50, 100, 200, 300, 400, 500, 600, 700, 800, 900 |
| Purple | [tailwindcss.com/docs/colors](https://tailwindcss.com/docs/colors) | 100, 500, 600, 800 |
| Yellow | [tailwindcss.com/docs/colors](https://tailwindcss.com/docs/colors) | 50, 200, 600, 700 |

---

## Known Inconsistency — Landing Page

The landing page uses [DaisyUI](https://daisyui.com/components/button/) component tokens
(`btn-primary`, `btn-secondary`, `btn-accent`, `btn-ghost`, `alert-info`) which pull from the
DaisyUI default theme rather than the hand-coded Tailwind palette above. These will render in
DaisyUI's default blues/purples and are **not yet aligned** with the rest of the app.

> **Feedback opportunity:** Should the landing page adopt the same blue/green palette, or is the
> DaisyUI default theme acceptable there?
