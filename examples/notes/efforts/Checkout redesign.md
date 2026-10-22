---
tags:
  - web
  - payments
about: "one-page checkout to cut drop-off at the payment step"
status: active
priority: 1
target: 2026-10-22
next: "Ship the new address form behind the flag"
updated: 2026-10-21
resume: "claude --resume checkout-redesign"
---
**Where I am:** The single-page layout is merged behind the `new_checkout` flag. Address and
payment forms work; the order summary still uses the old component.

**Clarify with Alice + Bob:**
- [ ] Do we keep guest checkout in the first release, or require an account?
- [ ] Which payment errors should stay on the page instead of sending people back
      to the cart?
- [x] Is the flag on for staff accounts?

**Decide myself:**
- [ ] Ship with the old order summary, or wait two days for the new one
- [ ] Pick the copy for the "Pay now" button

**Then:** finish the address form → turn the flag on for 10% of visitors on Monday.

refs: design file "Checkout v3" · ticket WEB-412
