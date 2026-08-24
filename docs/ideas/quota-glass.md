# QuotaGlass

## Problem Statement

How might we let frequent Codex/Work users understand their remaining allowance at a glance, without opening Usage settings or handing credentials to another app?

## Recommended Direction

Build one adaptive desktop hourglass. It represents whichever quota window is currently most constrained and always labels the selected window and reset time. The app is a companion to the official ChatGPT/Codex desktop client and reads only through its local App Server protocol.

The product wins through calm, ambient awareness rather than dashboard depth. When quota reaches zero, the glass remains visibly empty until the backend confirms a reset; subtle upward particles communicate waiting without inventing available capacity.

## Key Assumptions to Validate

- [ ] The official Codex App Server continues to expose read-only rate-limit snapshots across client updates.
- [ ] Users accept the official ChatGPT/Codex app as a prerequisite.
- [ ] Showing the most constrained window is more useful than fixing the display to one period.

## MVP Scope

- One draggable desktop-level hourglass across all Spaces
- Remaining percentage, selected window, reset countdown, and compact details
- Immediate refresh on App Server notification and a 45-second fallback poll
- Clear missing-client, sign-in, stale, incompatible-version, and offline states
- Optional launch at login
- Native Apple Silicon app for macOS 14+

## Not Doing (and Why)

- Ordinary ChatGPT message, image, or voice limits — they are not provided by this data contract.
- Independent OpenAI login — it expands the security and compatibility surface unnecessarily.
- Accessibility scraping or traffic interception — these require sensitive permissions and are too brittle for a public utility.
- History charts, forecasts, alerts, or telemetry — they dilute the single glanceable job.
- Intel, iOS, Mac App Store, or cloud versions — they do not validate the core experience.

## Open Questions

There are no product decisions blocking the MVP. App Server protocol stability remains the primary technical assumption under continuous test.
