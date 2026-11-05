# Native Emoticons Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline, task by task.

**Goal:** Four-platform native image emoticons in chat and scrolling danmaku.
**Architecture:** Immutable ordered message parts; room-scoped official catalogs; shared image providers; locally maintained canvas renderer with inline image slots.
**Tech Stack:** Dart, Flutter, existing Dio/protobuf/Tars and canvas_danmaku 0.3.3.
**Spec:** docs/superpowers/specs/2026-11-05-native-emoticons-design.md

## Global Constraints
- Preserve all existing changes and user data. Back up touched files before atomic replacement.
- Do not edit pub-cache or disable TLS verification. Retain renderer license.
- Preserve raw text for filtering/copy and failed-image fallback. Do not claim unavailable remote resources supported.

## Review Focus
- Malformed or unknown protocol metadata must not drop the message.
- Duplicate/overlapping tokens, repeated images, and plain bracket text retain order.
- Room catalog failures or late replies cannot contaminate another room.
- Animation, image load failures, and disposal must release listeners and preserve fallback.
- Danmaku widths, scaling, opacity and track spacing account for images.

## Task 1: Protocol and catalog
- [x] Write failing tests for message parts, longest token match, malformed URLs, B站 extra, 抖音 rich text, official directory shapes.
- [x] Run core tests with the existing resolved dependencies; observe RED.
- [x] Add LiveEmoticon/LiveMessagePart and parser/catalog utilities; integrate native parsers without dropping original text.
- [x] Run focused tests to GREEN.

## Task 2: Chat and scrolling renderer
- [x] Write failing widget/renderer tests: mixed spans, failed image text, animated frames, exact slot widths, cleanup.
- [x] Vendor licensed canvas renderer into app lib/widgets/danmaku; extend paragraph slots/image drawing; switch app imports.
- [x] Add shared cached image provider and chat spans; pass parts through controller.
- [x] Run focused tests to GREEN, including original plain text behavior.

## Task 3: Room lifecycle and verification
- [x] Load official catalogs asynchronously per room; use message metadata immediately; refresh displayed chat on catalog arrival.
- [x] Test stale replies, unavailable APIs, repeated requests.
- [x] Run core/app suites and targeted analysis; report pre-existing failures separately.
- [x] Inspect actual platform responses and record verified coverage and remaining gaps.
- [x] Review final diff. No commit or publishing unless requested.

## Execution record
- Implemented inline; all existing unrelated modifications retained. No commit/push.
- Independent reviewer reported directory retry and font metrics P2 issues; both fixed with regression tests and re-reviewed clean.
- Local installers/APKs staged in dist; no remote publishing.
- Final test results and unverified coverage are recorded in dist/SimpleLive-v2.0.7-emoticons-checks.md.
