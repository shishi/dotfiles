---
name: adr
description: Manage Architecture Decision Records and ADR-aligned development. Use when user says "we should use", "let's go with", asks "why did we choose X?", implements a feature that may have an ADR, updates ADR status, or needs to check alignment with existing decisions.
---

# INSTRUCTIONS

Manage Architecture Decision Records (ADRs) throughout their lifecycle: read existing decisions, write new ones, and ensure development aligns with documented decisions.

- **Template**: See `template.md` for the MADR structure (status, context, drivers, options, consequences)
- **Operations**: See `operations.md` for directory discovery, naming conventions, commit integration, deprecation (`_` prefix), and ADR-aligned development workflow
- **Queries**: See `queries.md` for finding ADRs by topic, status, or relationship

## Modes

### Read Mode
**Trigger**: "why did we choose X?", "what's our approach to Y?", "is there an ADR for Z?"

1. Discover ADR directory (see `operations.md`)
2. Search for relevant ADRs by keyword/topic
3. Summarize the decision and its rationale
4. Note if the ADR is active, deprecated, or superseded

### Write Mode
**Trigger**: A requested architectural decision record, or a project decision that the repository's documentation policy requires recording. A conversational choice or agent execution plan alone does not require an ADR.

1. Check for existing ADRs on the topic (may need to supersede)
2. Establish the project decision and intended readers from the request and existing evidence
3. Draft ADR using `template.md` and writing-prose's content and publication rules. Keep private environment knowledge in private memory and agent working notes outside Git
4. Save the requested project record in the established ADR location; commit only within the authorized workflow

### ADR-Aligned Development Mode
**Trigger**: Implementing features, making architectural changes, deviating from existing patterns

1. **Before implementation**: Check for relevant ADRs
2. **During implementation**: Reference ADR in commits
3. **On completion**: Update ADR status (proposed → accepted)
4. **On deviation**: Create superseding ADR, deprecate old one with `_` prefix

## Quality Checklist

Before finalizing an ADR:

- [ ] Title clearly states the decision (not the problem)
- [ ] Context explains WHY this decision is needed now
- [ ] At least 2 options were genuinely considered
- [ ] Decision drivers link to actual project constraints
- [ ] Consequences include both positive AND negative impacts
- [ ] Confirmation section describes how to validate the decision

## Anti-Patterns

- **Decision without options**: Always document alternatives considered
- **Vague consequences**: Be specific about trade-offs
- **Missing "why"**: The ADR should answer "why this, why now"
- **Orphan ADRs**: Link to related ADRs when relevant
- **Stale ADRs**: Update status when implemented or superseded
- **Undocumented deviation**: If you deviate from an ADR, create a new one

## Reference

Based on [MADR - Markdown Architectural Decision Records](https://adr.github.io/madr/) (Version 4.0, 2024)
