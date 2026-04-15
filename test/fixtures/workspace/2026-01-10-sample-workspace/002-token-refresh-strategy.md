---
created: 2026-01-12T14:00+09:00
topic: 2026-01-10-sample-workspace
type: decision
tags: [infrastructure]
mentions: [projects/sample-project]
---

# Token Refresh Strategy Design

## Problem

The current authentication flow has a short token expiration (15 minutes), causing users to experience frequent session timeouts. A refresh token implementation is needed.

## Options Considered

### A. Silent Refresh (Recommended)
- Automatic renewal in the background before expiration
- No impact on UX
- Implementation cost: Medium

### B. Sliding Session
- Extends expiration based on activity detection
- Higher security risk
- Implementation cost: Low

### C. Refresh Token Rotation
- Reissues token with each refresh
- Highest security but complex
- Implementation cost: High

## Decision

**Option A: Silent Refresh** is adopted. A background refresh will be executed 2 minutes before expiration. Auth0's SDK has this functionality built in, so additional implementation is minimal.

## Implementation Notes

- Use Auth0's `checkSession()`
- `tokenRefreshMargin: 120` to refresh 2 minutes before expiration
- On refresh failure, redirect to login screen
