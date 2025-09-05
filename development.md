# Kalvian Roots Development Guide

## Branch Structure

- `main` - Production branch
- `stable-working` - Protected stable version (all citations working)
- `feature/next-family-cache` - Current feature development branch
- `backup-ios-attempt` - Previous iOS compatibility work

## Important Tags

- `v1.0-stable` - Tagged stable version before cache feature (created Nov 2024)

## Safety Commands

### If something goes wrong during development:
```bash
# Quick escape to stable version
git checkout stable-working

# Or reset feature branch to stable tag
git checkout feature/next-family-cache
git reset --hard v1.0-stable
```

### To see current branch:
```bash
git branch
```

### To see all branches including remote:
```bash
git branch -a
```

## Current Development: Next Family Cache

Adding background processing to pre-fetch the next family while working on current family citations.

Features being added:
- Background extraction of next family after blank line
- CoreData + CloudKit caching for multi-device sync
- "Next" button appears when next family is ready
- Non-intrusive error handling

## Working Workflow

1. Always develop on feature branches
2. `stable-working` branch should never be modified directly
3. Test features on families already completed before using on new work
4. Run app from Xcode while on `feature/next-family-cache` branch for testing

## Git Reminders

- This repo uses GitHub: https://github.com/michaelbendio/Kalvian-Roots
- Working directory: ~/Kalvian-Roots
- .gitignore is configured to exclude Xcode user files and .DS_Store

## Testing Approach

- Test cache with already-completed families first
- Verify citations match exactly before using on new families
- Background processing errors should not interrupt current work

## How to Use This Guide

When working with a new AI assistant or returning after a break:
1. Show them this file: `cat DEVELOPMENT.md`
2. Tell them which branch you're currently on: `git branch`
3. Explain what you're trying to accomplish

## Rollback Procedures

If the cache feature causes issues:
```bash
# Option 1: Switch to stable version immediately
git checkout stable-working

# Option 2: Reset feature branch to stable
git checkout feature/next-family-cache
git reset --hard v1.0-stable

# Option 3: Stash changes and switch
git stash
git checkout stable-working
```

## Cache Feature Implementation Status

- [ ] FileManager extension for finding next family
- [ ] FamilyNetworkCache class with CoreData
- [ ] JuuretApp integration with cache
- [ ] UI updates for Next button
- [ ] Background processing queue
- [ ] Error handling and notifications
- [ ] Testing with completed families
- [ ] CloudKit sync configuration

