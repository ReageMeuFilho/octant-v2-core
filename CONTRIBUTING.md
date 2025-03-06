# Contribution Guide for Octant V2 Core

## 🌟 Our Development Philosophy

At Golem Foundation, we believe in creating maintainable, high-quality code through thoughtful collaboration. This guide outlines our expectations and best practices for contributing to the project.

## 📋 Pull Request Guidelines

### Atomic Commits
- Each commit should represent a single logical change
- Use clear, descriptive commit messages that explain *why* the change was made
- Follow the [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/) format: `type(scope): message` (e.g., `fix(rewards): correct calculation for staking rewards`)
- Avoid mixing unrelated changes in a single commit

### PR Management
As PRs get bigger, time to review them scales super-linearly. And long-standing PRs create lots of merge conflict and duplicate work. It's much cheaper for the team to make small and prompt changes to codebase than big and belated changes.


- Keep PRs focused on a single feature, bug fix, or improvement
- Aim for PRs under 300 lines of code when possible
- Split large features into smaller, sequential PRs
- Include relevant tests and documentation with your changes
- Review existing PRs (if requested) before creating new ones
- Help merge ready PRs to prevent accumulation
- Set aside a time for PR reviews daily
- Rebase your branch before requesting review to ensure it's up-to-date

## 🧩 Code Quality Principles

### Simplicity First
Main time cost of developing smart-contract is audits, not development itself. By solving things in simplest, clearest way we can reduce this cost dramatically.

- Implement the simplest solution that meets requirements
- Avoid premature optimization or over-engineering
- Write self-documenting code with clear variable and function names, with clear intent
- Use comments as a last resort when things are not clear enough

### Maintainability
- Aim for high coherence and loose coupling
- Adhere to [SOLID Principles](https://hackernoon.com/solid-principles-in-smart-contract-development) so we can ensure solidity (pun intended) of our code 
- Consider future (maintenance, or other) costs in your design decisions

### Technical Debt Management
- Apply the ["Boy Scout Rule"](https://deviq.com/principles/boy-scout-rule): Leave the code better than you found it
- Address small issues before they become big problems
- Document what you stumble upon and can't address now

## 🔍 Code Review Process

### As an Author
- Self-review your code before requesting reviews
- Provide context in the PR description about what changes were made and why
- Be open to feedback and willing to make changes
- Use the PR description to highlight areas where you'd like specific feedback

### As a Reviewer
- Be respectful and constructive in your feedback
- Focus on the code, not the person
- Stay in the scope of the PR during your review
- Be specific, leave no room for confusion
- Try to approve ASAP when concerns are addressed
## 🛠️ Development Workflow
- We use [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) as Git branching model.
- We use a pre-commit hook to automatically format, lint and test, ensuring no surprises on continuous integration run.
## 🤝 Communication
- Use clear, verbose language in all communications
- Ask questions when something isn't clear
- Share progress and blockers with the team
- Be mindful of others' time and priorities

## 🔒 Security Considerations
- Always prioritize security and only then consider gas optimizations
- Follow established security patterns for smart contracts
- Consider edge cases and potential attack vectors
- Document security assumptions and considerations

---

Thank you for contributing to Octant V2 Core!
