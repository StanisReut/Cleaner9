# Additional-state reference coverage

Reference is the cached Cleaner-9 Figma snapshot from 2026-11-10 (198 frames, widths 375pt; heights812,1115 and216pt). No live Figma tool is available in this turn. This pass does not claim a newer design revision was fetched.

| Additional state | Reference availability | What can be established |
|---|---|---|
| Maximum Dynamic Type | No dedicated maximum-text frames in the cached198-frame inventory | Legibility, layout adaptation, reachable actions and preservation of design tokens; not pixel identity |
| Real media/contact/calendar values | Corresponding normal screen chrome exists | Structure and styling; actual counts, names and images intentionally differ |
| Photos access denied | No exact denial frame in inventory | Readable explanation and recovery controls; design-system consistency only |
| Contacts access denied | No exact denial frame in inventory | Readable explanation and recovery controls; design-system consistency only |
| Calendar access denied | No exact denial frame in inventory | Readable explanation and recovery controls; design-system consistency only |
| Email service unavailable |147:2969 provides main card/Retry; production adds service-unconfigured disclosure | Compare source chrome and separately inspect extra live disclosure |
| Purchases unconfigured | No exact unconfigured alert frame;159:3259 is a different restore-failure state | Inspect live alert separately; do not substitute fixture purchase success/error for real integration |
| Password lookup error/cancellation | No deterministic error route in existing fidelity inventory | Not runtime-proven by screenshot of weak/strong fixture; requires controlled network responses |
| Cloud media loading/error/retry | No deterministic cloud-failure route | Needs cloud-only test media and controlled connectivity; no success inferred from local-media preview |
| Partial restore or corrupt backup failure | No exact source failure frame / deterministic runtime route | Needs safe failure injection and separate reference decision; no failure claimed from success screenshots |
| Background removal inference/export failure | Existing chooser/processing/denied/saved frames do not specify inference failures | Requires runtime reproduction; successful Vision segmentation still requires physical-device verification |
| Native iOS picker/share/permission UI | System-owned and OS-version-dependent | Previously functionally exercised; cannot certify app-authored pixel identity |

Current production configuration leaves subscription product IDs empty and support/legal endpoints unset. Live Settings errors are not equivalent to fidelity previews. The email entry action currently goes to unavailable without sending the address; supplemental UI checks can safely use alex@example.com.

Long arbitrary names, every OS/runtime and physical-device-only outcomes remain outside the fixed228-cell matrix unless explicitly recorded as supplemental evidence.
