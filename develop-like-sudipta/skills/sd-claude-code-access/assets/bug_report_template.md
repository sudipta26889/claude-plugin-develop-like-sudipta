# Bug: <bug-id>

> File location: `<workspace>/.cc/bugs/<bug-id>.md`
> `<bug-id>` = `phase-<N>-bug-<short-slug>` — e.g. `phase-3-bug-cart-total-off-by-tax`

## Metadata
- **Bug ID:** `phase-<N>-bug-<short-slug>`
- **Date opened:** YYYY-MM-DD HH:MM TZ
- **Phase:** <N>
- **Linked phase directive:** `.cc/phase-<N>.md`
- **Linked phase test record:** `docs/e2e-testing/phase-<N>-<feature-slug>.md`
- **Severity:** `<critical | high | medium | low>`
- **Discovered by:** `<verify-gate | browser-test | manual | re-run>`
- **Discovered at commit:** `<git sha at time of failure>`

## Symptom (one sentence)
<What's wrong, as a user would describe it. e.g. "Cart total shows $10 but should be $11 because tax wasn't applied.">

## Captured evidence

### Exact failing command
```
<the shell command that produced the red, copy-paste verbatim>
```

### Exit code
`<N>`

### Last 200 lines of stdout+stderr
```
<verbatim — no editing, no truncation, no "..." placeholders>
```

### Failing assertion / test name
`<path/to/test_file.py::TestClass::test_method>` — line `<NN>`
`<assertion text with expected vs actual>`

### Stack trace (if present)
```
<verbatim stack trace>
```

### For browser bugs only

**Screenshot path:** `docs/e2e-testing/screenshots/phase-<N>/bug-<id>-evidence.png`

**Console messages (verbatim):**
```
[error] Uncaught TypeError: Cannot read property 'x' of undefined
    at handleSubmit (Form.tsx:42)
```

**Network requests of interest:**
| Method | URL | Status | Body excerpt |
|---|---|---|---|
| POST | /api/cart/total | 200 | `{"total": "10.00"}` |

**DOM excerpt around the broken element:**
```html
<button disabled aria-label="Submit">Submit</button>
```

### Files implicated
Resolved to repo-relative paths:
- `src/cart/calculate.py:42` — likely root cause
- `frontend/components/CartTotal.tsx:18` — affected display

### Phase acceptance criterion this violates
> "When a user adds items totaling $10 with a 10% tax rate, the displayed total must be $11."
(Quoted from `.cc/phase-<N>.md`, section "Acceptance".)

## Reproduction steps (write BEFORE fixing — both tests must go red)

### Unit-layer reproduction
**Test path:** `tests/unit/test_<bug-id>_<intent>.py` (or equivalent)
**Naming:** `test_<bug-id>_<intent>`
**Scope:** smallest possible — call the broken function directly, no full-stack mocks.
**Status before fix:** ☐ red ☐ green  *(must be red for the bug-specific reason)*
**Verification command:** `pytest tests/unit/test_<bug-id>_<intent>.py -v`

```python
# Sketch of the test (final version in the test file):
def test_<bug_id>_<intent>():
    # arrange: data that triggers the bug
    cart = Cart(items=[Item(price=Decimal("10.00"))], tax_rate=Decimal("0.10"))
    # act
    total = cart.calculate_total()
    # assert the CORRECT behavior (this fails on the bug)
    assert total == Decimal("11.00"), f"expected $11.00, got {total}"
```

### Browser-layer reproduction
**Test path:** `docs/e2e-testing/specs/phase-<N>.spec.ts` — new `test.step('bug-<id>: ...')`
**Status before fix:** ☐ red ☐ green  *(must be red, user-visible)*
**Verification command:** `npx playwright test --config=docs/e2e-testing/specs/playwright.config.ts phase-<N>.spec.ts`

```typescript
test.step('bug-<id>: cart total includes tax', async () => {
  await page.goto('/cart');
  await page.getByRole('button', { name: 'Add $10 item' }).click();
  await page.getByRole('link', { name: 'Checkout' }).click();
  await expect(page.getByText('Total: $11.00')).toBeVisible();
});
```

## Hypothesis (optional, keep short)
<One paragraph. Let CC investigate. Don't over-prescribe — listing the broken function and the wrong return value is enough.>

## Fix directive
**Location:** `<workspace>/.cc/phase-<N>-fix.md`
**Trigger sent:** `Read \`.cc/phase-<N>-fix.md\` and apply the fix per the bug-driven-TDD protocol.`
**Sent at:** YYYY-MM-DD HH:MM

## Confirmation (after CC's fix lands)

| Light | Test | Status | Run at | Commit |
|---|---|---|---|---|
| 4a | new unit test (`<path>`) | ☐ green | YYYY-MM-DD HH:MM | `<sha>` |
| 4b | new browser test step | ☐ green | YYYY-MM-DD HH:MM | `<sha>` |
| 4c | full verify-gate | ☐ green | YYYY-MM-DD HH:MM | `<sha>` |
| 4d | phase-<N> browser test | ☐ green | YYYY-MM-DD HH:MM | `<sha>` |

**Final state:** ☐ resolved ☐ escalated (after 3 failed attempts) ☐ not-reproducible

## Notes
<Free-form. Anything surprising. Anything the next person should know.>
