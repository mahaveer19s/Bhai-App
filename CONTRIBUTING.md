# Contributing to BHAI

Thank you for your interest in contributing to BHAI! This guide walks you through setting up your local development environment, making changes, running tests, and submitting pull requests.

---

## 1. Development Workflow

1. **Fork & Clone:**
   ```bash
   git clone https://github.com/mahaveer19s/Bhai-App.git
   cd Bhai-App
   ```
2. **Create a Feature Branch:**
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. **Configure Local Environment:**
   ```bash
   cp .env.example .env
   cd backend
   cp .env.example .env
   ```
4. **Install Dependencies:**
   ```bash
   # Backend
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install -r requirements.txt
   ```
5. **Run Test Suites:**
   ```bash
   pytest -v
   ```

---

## 2. Coding Guidelines & Commit Standards

- **No Secrets in Code:** Never commit API keys, `.env` files, or production credentials.
- **Coordinate Validation:** Ensure all new location features validate against Null Island `(0,0)` and out-of-bound ranges.
- **Async Concurrency:** Backend handlers must remain non-blocking. Never use long-polling HTTP requests for streaming.
- **Commit Messages:** Follow conventional commits (e.g., `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`).

---

## 3. Pull Request Process

1. Ensure all 21 automated backend tests pass.
2. Submit your PR against the `main` branch using the provided PR template.
3. Link any associated GitHub issues.
