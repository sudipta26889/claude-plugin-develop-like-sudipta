// source: assets/playwright.config.template.ts (sd-claude-code-access)
// Scaffolded once per project. Safe to edit by hand after copy.
// Cross-browser projects are driven by <workspace>/.cc/config.json → "browsers".

import { defineConfig, devices } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const DEV_SERVER_URL = process.env.DEV_SERVER_URL || 'http://localhost:5173';

// Read browsers list from <workspace>/.cc/config.json → "browsers"
// Default: ["chromium"] for speed. Allowed: chromium, firefox, webkit, mobile-chrome, mobile-safari
const browsersFromConfig = (() => {
  try {
    const configPath = path.join(__dirname, '..', '..', '..', '.cc', 'config.json');
    if (fs.existsSync(configPath)) {
      const cfg = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      if (Array.isArray(cfg.browsers) && cfg.browsers.length > 0) return cfg.browsers;
    }
  } catch (_) { /* fall through to default */ }
  return ['chromium'];
})();

const projectMap: Record<string, any> = {
  'chromium':       { name: 'chromium',       use: { ...devices['Desktop Chrome'] } },
  'firefox':        { name: 'firefox',        use: { ...devices['Desktop Firefox'] } },
  'webkit':         { name: 'webkit',         use: { ...devices['Desktop Safari'] } },
  'mobile-chrome':  { name: 'mobile-chrome',  use: { ...devices['Pixel 5'] } },
  'mobile-safari':  { name: 'mobile-safari',  use: { ...devices['iPhone 13'] } },
};

const projects = browsersFromConfig
  .filter((b: string) => b in projectMap)
  .map((b: string) => projectMap[b]);

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  retries: process.env.CI ? 2 : 0,
  reporter: [['html', { outputFolder: '../playwright-report' }], ['list']],
  use: {
    baseURL: DEV_SERVER_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: projects.length > 0 ? projects : [projectMap.chromium],
});
