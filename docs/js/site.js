/**
 * Voxbrief · Simplicity, Professional & Geek Interactive Controller
 * Native On-Device Audio Intelligence Showcase
 */

(function () {
  'use strict';

  // ==========================================================================
  // 01. THEME MANAGEMENT (Dark / Light with System Preference & Storage)
  // ==========================================================================
  const THEME_KEY = 'voxbrief-theme';

  function getSystemTheme() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches
      ? 'light'
      : 'dark';
  }

  function getStoredTheme() {
    try {
      const saved = localStorage.getItem(THEME_KEY);
      if (saved === 'light' || saved === 'dark') return saved;
    } catch (e) {
      console.warn('Storage unavailable:', e);
    }
    return getSystemTheme();
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    const metaTheme = document.getElementById('themeColorMeta');
    if (metaTheme) {
      metaTheme.setAttribute('content', theme === 'light' ? '#fafbfc' : '#08090d');
    }
    const toggles = document.querySelectorAll('.theme-toggle');
    toggles.forEach(btn => {
      const next = theme === 'light' ? 'dark' : 'light';
      btn.setAttribute('aria-label', `Switch to ${next} theme (Shortcut: T)`);
      btn.setAttribute('title', `Switch to ${next} theme (Shortcut: T)`);
    });
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute('data-theme') || 'dark';
    const next = current === 'light' ? 'dark' : 'light';
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch (e) {}
    applyTheme(next);
    showToast(`Switched to ${next} theme`);
  }

  // Setup OS change listener
  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', e => {
      if (!localStorage.getItem(THEME_KEY)) {
        applyTheme(e.matches ? 'light' : 'dark');
      }
    });
  }

  // ==========================================================================
  // 02. TOAST NOTIFICATION UTILITY
  // ==========================================================================
  let toastTimeout = null;
  function showToast(message) {
    let toast = document.getElementById('siteToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'siteToast';
      toast.className = 'toast-notice';
      document.body.appendChild(toast);
    }
    toast.innerHTML = `<span style="color:#38bdf8;">⚡</span> ${message}`;
    toast.classList.add('show');
    clearTimeout(toastTimeout);
    toastTimeout = setTimeout(() => {
      toast.classList.remove('show');
    }, 2400);
  }

  // ==========================================================================
  // 03. INTERACTIVE WORKBENCH (Two-Stage Transformation Sandbox)
  // ==========================================================================
  const WORKBENCH_DATA = [
    {
      name: "1. Distributed Cache RFC",
      timer: "00:24 / 01:10",
      totalSeconds: 70,
      currentSeconds: 24,
      raw: `"hey team, <span class='filler-token'>so yeah</span> quick RFC thought on our distributed caching layer. requirement one is client-side reads must hit local memory cache with zero network round trips. requirement two is cache invalidation events must be broadcast over <span class='jargon-token'>gRPC</span> streams with backpressure. condition 1 if the node loses consensus, immediately degrade to read-only replica mode. condition 2 if memory pressure exceeds 85%, evict via least-recently-used policy. <span class='filler-token'>um</span> make sure to benchmark on <span class='jargon-token'>Apple Silicon</span> unified memory."`,
      rendered: `
        <div class="spec-title-h1">RFC: Distributed Cache Consensus &amp; Invalidation</div>
        <div class="spec-callout">Decoupled in-memory caching tier with backpressure-aware gRPC event stream and fail-safe consensus degradation.</div>
        
        <div class="spec-h2">🎯 Technical Requirements</div>
        <ul class="spec-bullets">
          <li>Client reads must resolve from local in-memory L1 cache with 0ms network overhead</li>
          <li>Broadcast invalidation signals across cluster via gRPC bidirectional streaming</li>
          <li>Enforce strict unified memory bounds with deterministic LRU eviction</li>
        </ul>

        <div class="spec-h2">🔢 Execution Logic</div>
        <ul class="spec-bullets">
          <li><strong>Consensus Partition:</strong> Degrade to read-only replica if heartbeat quorum fails</li>
          <li><strong>Memory Threshold:</strong> Trigger LRU pruning when heap memory utilization &gt; 85%</li>
        </ul>

        <div class="spec-h2">✅ Action Items (Click to complete)</div>
        <ul class="spec-checklist">
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Benchmark unified memory throughput on M3 / M4 Apple Silicon</span>
          </li>
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Implement gRPC streaming backpressure controller with flow tokens</span>
          </li>
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Verify partition fail-safe state transitions under network chaos</span>
          </li>
        </ul>

        <div class="spec-tag-row">
          <span class="spec-tag">#DistributedSystems</span>
          <span class="spec-tag">#gRPC</span>
          <span class="spec-tag">#Consensus</span>
          <span class="spec-tag">#AppleSilicon</span>
        </div>
      `,
      markdown: `# RFC: Distributed Cache Consensus & Invalidation\n\n> Decoupled in-memory caching tier with backpressure-aware gRPC event stream and fail-safe consensus degradation.\n\n### 🎯 Technical Requirements\n- Client reads must resolve from local in-memory L1 cache with 0ms network overhead\n- Broadcast invalidation signals across cluster via gRPC bidirectional streaming\n- Enforce strict unified memory bounds with deterministic LRU eviction\n\n### 🔢 Execution Logic\n1. If node loses heartbeat quorum, immediately degrade to read-only replica mode\n2. If heap memory utilization exceeds 85%, trigger deterministic LRU eviction\n\n### ✅ Action Items\n- [ ] Benchmark unified memory throughput on M3 / M4 Apple Silicon\n- [ ] Implement gRPC streaming backpressure controller with flow tokens\n- [ ] Verify partition fail-safe state transitions under network chaos\n\n#DistributedSystems #gRPC #Consensus #AppleSilicon`,
      ast: `{\n  "template": "rfc_specification",\n  "title": "RFC: Distributed Cache Consensus & Invalidation",\n  "summary": "Decoupled in-memory caching tier with backpressure-aware gRPC event stream and fail-safe consensus degradation.",\n  "requirements": [\n    "Client reads must resolve from local in-memory L1 cache with 0ms network overhead",\n    "Broadcast invalidation signals across cluster via gRPC bidirectional streaming",\n    "Enforce strict unified memory bounds with deterministic LRU eviction"\n  ],\n  "conditions": [\n    "If node loses heartbeat quorum, immediately degrade to read-only replica mode",\n    "If heap memory utilization exceeds 85%, trigger deterministic LRU eviction"\n  ],\n  "actionItems": [\n    { "task": "Benchmark unified memory throughput on M3 / M4 Apple Silicon", "done": false },\n    { "task": "Implement gRPC streaming backpressure controller with flow tokens", "done": false },\n    { "task": "Verify partition fail-safe state transitions under network chaos", "done": false }\n  ],\n  "tags": ["DistributedSystems", "gRPC", "Consensus", "AppleSilicon"],\n  "metadata": {\n    "asr_engine": "WhisperKit CoreML",\n    "llm_engine": "Apple Foundation Model (SystemLanguageModel)",\n    "on_device_latency_ms": 842,\n    "network_bytes_sent": 0\n  }\n}`
    },
    {
      name: "2. Sprint Task Decomposition",
      timer: "00:15 / 00:38",
      totalSeconds: 38,
      currentSeconds: 15,
      raw: `"sprint breakdown for tomorrow's deploy. <span class='filler-token'>like</span> first thing is update the <span class='jargon-token'>PersonalDictionaryStore</span> regex matcher so technical terms like <span class='jargon-token'>CoreML</span> and <span class='jargon-token'>Metal</span> aren't mangled. then verify the <span class='jargon-token'>Apple Watch</span> complication tap latency on <span class='jargon-token'>watchOS 10</span>. <span class='filler-token'>um</span> and finally run the testflight release script for build 1.15.0."`,
      rendered: `
        <div class="spec-title-h1">Sprint Priorities &amp; Release Engineering</div>
        <div class="spec-callout">Sprint decomposition categorized under the Task List schema with technical jargon preservation.</div>
        
        <div class="spec-h2">🎯 Sprint Focus</div>
        <ul class="spec-bullets">
          <li>Harden technical dictionary regex word boundaries against LLM hallucination</li>
          <li>Validate Apple Watch complication instant capture responsiveness</li>
          <li>Automate Release Build 1.15.0 signing and TestFlight distribution</li>
        </ul>

        <div class="spec-h2">✅ Sprint Checklist (Click to complete)</div>
        <ul class="spec-checklist">
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Update PersonalDictionaryStore regex engine for CoreML and Metal tokens</span>
          </li>
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Benchmark watchOS 10 complication tap-to-record latency (&lt;120ms)</span>
          </li>
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Execute ./scripts/release_testflight.sh for build v1.15.0 upload</span>
          </li>
        </ul>

        <div class="spec-tag-row">
          <span class="spec-tag">#Sprint</span>
          <span class="spec-tag">#watchOS</span>
          <span class="spec-tag">#CoreML</span>
          <span class="spec-tag">#Release</span>
        </div>
      `,
      markdown: `# Sprint Priorities & Release Engineering\n\n> Sprint decomposition categorized under the Task List schema with technical jargon preservation.\n\n### 🎯 Sprint Focus\n- Harden technical dictionary regex word boundaries against LLM hallucination\n- Validate Apple Watch complication instant capture responsiveness\n- Automate Release Build 1.15.0 signing and TestFlight distribution\n\n### ✅ Sprint Checklist\n- [ ] Update PersonalDictionaryStore regex engine for CoreML and Metal tokens\n- [ ] Benchmark watchOS 10 complication tap-to-record latency (<120ms)\n- [ ] Execute ./scripts/release_testflight.sh for build v1.15.0 upload\n\n#Sprint #watchOS #CoreML #Release`,
      ast: `{\n  "template": "task_list",\n  "title": "Sprint Priorities & Release Engineering",\n  "summary": "Sprint decomposition categorized under the Task List schema with technical jargon preservation.",\n  "actionItems": [\n    { "task": "Update PersonalDictionaryStore regex engine for CoreML and Metal tokens", "done": false },\n    { "task": "Benchmark watchOS 10 complication tap-to-record latency (<120ms)", "done": false },\n    { "task": "Execute ./scripts/release_testflight.sh for build v1.15.0 upload", "done": false }\n  ],\n  "tags": ["Sprint", "watchOS", "CoreML", "Release"],\n  "metadata": {\n    "asr_engine": "WhisperKit CoreML",\n    "llm_engine": "Apple Foundation Model",\n    "on_device_latency_ms": 510,\n    "network_bytes_sent": 0\n  }\n}`
    },
    {
      name: "3. Incident Architecture Review",
      timer: "00:20 / 00:48",
      totalSeconds: 48,
      currentSeconds: 20,
      raw: `"incident debrief from this morning's pipeline crash. root cause was <span class='jargon-token'>MLX Swift</span> GPU allocator attempting to allocate heap buffers in the simulator environment which throws an uncatchable C++ abort. decision we strictly enforced <span class='jargon-token'>isSupportedOnThisDevice</span> compile-time and runtime guards so simulator falls back gracefully to rule-based transformer. action items: verify unit test suite on both macOS and iOS simulator without crashes."`,
      rendered: `
        <div class="spec-title-h1">Incident Post-Mortem: Simulator MLX Metal Guard</div>
        <div class="spec-callout">Investigation into Simulator Metal allocation faults and enforcement of multi-tiered fallback architecture.</div>
        
        <div class="spec-h2">💡 Root Cause Analysis</div>
        <ul class="spec-bullets">
          <li>MLX Metal GPU allocator requires hardware heap storage modes absent in iOS Simulator</li>
          <li>Uncaught C++ abort bypassed standard Swift error handling across runtime boundaries</li>
        </ul>

        <div class="spec-h2">🛡 Architectural Remediation</div>
        <ul class="spec-bullets">
          <li>Strictly guard all MLX entry points behind <code>isSupportedOnThisDevice</code></li>
          <li>Default to native Apple Foundation Model and fallback to deterministic AST transformer</li>
        </ul>

        <div class="spec-h2">✅ Action Items (Click to complete)</div>
        <ul class="spec-checklist">
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Verify test suite runs green in iOS Simulator with MLX gracefully bypassed</span>
          </li>
          <li class="spec-check-item" onclick="toggleTask(this)">
            <span class="custom-checkbox">✓</span>
            <span class="check-label">Run macOS native unit test suite against real Apple Silicon GPU</span>
          </li>
        </ul>

        <div class="spec-tag-row">
          <span class="spec-tag">#PostMortem</span>
          <span class="spec-tag">#MLX</span>
          <span class="spec-tag">#Metal</span>
          <span class="spec-tag">#Architecture</span>
        </div>
      `,
      markdown: `# Incident Post-Mortem: Simulator MLX Metal Guard\n\n> Investigation into Simulator Metal allocation faults and enforcement of multi-tiered fallback architecture.\n\n### 💡 Root Cause Analysis\n- MLX Metal GPU allocator requires hardware heap storage modes absent in iOS Simulator\n- Uncaught C++ abort bypassed standard Swift error handling across runtime boundaries\n\n### 🛡 Architectural Remediation\n- Strictly guard all MLX entry points behind isSupportedOnThisDevice\n- Default to native Apple Foundation Model and fallback to deterministic AST transformer\n\n### ✅ Action Items\n- [ ] Verify test suite runs green in iOS Simulator with MLX gracefully bypassed\n- [ ] Run macOS native unit test suite against real Apple Silicon GPU\n\n#PostMortem #MLX #Metal #Architecture`,
      ast: `{\n  "template": "meeting_notes",\n  "title": "Incident Post-Mortem: Simulator MLX Metal Guard",\n  "summary": "Investigation into Simulator Metal allocation faults and enforcement of multi-tiered fallback architecture.",\n  "keyDecisions": [\n    "Strictly guard all MLX entry points behind isSupportedOnThisDevice",\n    "Default to native Apple Foundation Model and fallback to deterministic AST transformer"\n  ],\n  "actionItems": [\n    { "task": "Verify test suite runs green in iOS Simulator with MLX gracefully bypassed", "done": false },\n    { "task": "Run macOS native unit test suite against real Apple Silicon GPU", "done": false }\n  ],\n  "tags": ["PostMortem", "MLX", "Metal", "Architecture"],\n  "metadata": {\n    "asr_engine": "WhisperKit CoreML",\n    "llm_engine": "Deterministic AST Transformer",\n    "on_device_latency_ms": 112,\n    "network_bytes_sent": 0\n  }\n}`
    }
  ];

  let currentScenarioIdx = 0;
  let currentViewMode = 'rendered'; // 'rendered' | 'markdown' | 'ast'
  let isPlayingAudio = false;
  let waveTimer = null;

  function renderWorkbench() {
    const data = WORKBENCH_DATA[currentScenarioIdx];
    
    // Update Scenario Buttons
    document.querySelectorAll('.scenario-btn').forEach((btn, idx) => {
      btn.classList.toggle('active', idx === currentScenarioIdx);
      btn.setAttribute('aria-selected', idx === currentScenarioIdx ? 'true' : 'false');
    });

    // Update Timer & Audio bar
    const timerEl = document.getElementById('workbenchTimer');
    if (timerEl) timerEl.textContent = data.timer;
    updateWaveformRatio(data.currentSeconds / data.totalSeconds);

    // Update Raw Transcript
    const rawBox = document.getElementById('rawTranscriptBox');
    if (rawBox) rawBox.innerHTML = data.raw;

    // Update Spec View Mode
    updateSpecViewDisplay();
  }

  function updateSpecViewDisplay() {
    const data = WORKBENCH_DATA[currentScenarioIdx];
    const specContainer = document.getElementById('specDisplayArea');
    if (!specContainer) return;

    // Update view mode buttons
    document.querySelectorAll('.view-mode-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.mode === currentViewMode);
    });

    if (currentViewMode === 'rendered') {
      specContainer.innerHTML = `<div class="rendered-spec">${data.rendered}</div>`;
    } else if (currentViewMode === 'markdown') {
      specContainer.innerHTML = `<pre class="raw-code-view"><code>${escapeHtml(data.markdown)}</code></pre>`;
    } else if (currentViewMode === 'ast') {
      specContainer.innerHTML = `<pre class="raw-code-view"><code>${escapeHtml(data.ast)}</code></pre>`;
    }
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  window.switchScenario = function (idx) {
    currentScenarioIdx = idx;
    renderWorkbench();
  };

  window.setViewMode = function (mode) {
    currentViewMode = mode;
    updateSpecViewDisplay();
  };

  window.toggleTask = function (el) {
    el.classList.toggle('checked');
    const label = el.querySelector('.check-label');
    if (label) {
      showToast(el.classList.contains('checked') ? 'Task completed ✓' : 'Task reopened');
    }
  };

  window.copyCurrentSpec = function () {
    const data = WORKBENCH_DATA[currentScenarioIdx];
    let contentToCopy = data.markdown;
    let label = 'Markdown';
    if (currentViewMode === 'ast') {
      contentToCopy = data.ast;
      label = 'AST JSON';
    }
    navigator.clipboard.writeText(contentToCopy).then(() => {
      showToast(`${label} copied to clipboard! ✓`);
    }).catch(() => {
      showToast('Clipboard access failed');
    });
  };

  window.togglePlaySimulation = function () {
    isPlayingAudio = !isPlayingAudio;
    const playIcon = document.getElementById('playIcon');
    const pauseIcon = document.getElementById('pauseIcon');
    const bars = document.querySelectorAll('.waveform-bar');

    if (isPlayingAudio) {
      if (playIcon) playIcon.style.display = 'none';
      if (pauseIcon) pauseIcon.style.display = 'block';
      waveTimer = setInterval(() => {
        bars.forEach(b => {
          const h = Math.floor(Math.random() * 80) + 15;
          b.style.height = h + '%';
        });
      }, 120);
      showToast('Simulating audio playback (AAC @ 32kHz)');
    } else {
      if (playIcon) playIcon.style.display = 'block';
      if (pauseIcon) pauseIcon.style.display = 'none';
      clearInterval(waveTimer);
    }
  };

  function updateWaveformRatio(ratio) {
    const bars = document.querySelectorAll('.waveform-bar');
    const activeThreshold = Math.round(ratio * bars.length);
    bars.forEach((b, i) => {
      b.classList.toggle('active', i <= activeThreshold);
    });
  }

  // Scrubber click handler
  function initWaveformScrubber() {
    const scrubber = document.getElementById('waveformScrubber');
    if (scrubber) {
      scrubber.addEventListener('click', e => {
        const rect = scrubber.getBoundingClientRect();
        const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        updateWaveformRatio(ratio);
        const data = WORKBENCH_DATA[currentScenarioIdx];
        const curSec = Math.round(ratio * data.totalSeconds);
        const fmt = s => (s < 10 ? '0' : '') + s;
        const timerEl = document.getElementById('workbenchTimer');
        if (timerEl) {
          timerEl.textContent = `00:${fmt(curSec)} / 00:${fmt(data.totalSeconds)}`;
        }
      });
    }
  }

  // ==========================================================================
  // 04. DEVELOPER CLI TERMINAL TAB SWITCHER
  // ==========================================================================
  const CLI_COMMANDS = {
    setup: `# 1. Clone repository\ngit clone https://github.com/tianhaoz95/voxbrief.git\ncd voice-note\n\n# 2. Generate Xcode project via XcodeGen\nxcodegen generate\n\n# 3. Resolve WhisperKit & MLX dependencies\nxcodebuild -resolvePackageDependencies -project Voxbrief.xcodeproj -scheme Voxbrief`,
    test: `# Run full test suite across macOS & iOS\n./scripts/run_unit_tests.sh\n\n# Or run specific test directly:\nxcodebuild test \\\n  -project Voxbrief.xcodeproj \\\n  -scheme VoxbriefMac \\\n  -destination 'platform=macOS' \\\n  CODE_SIGNING_ALLOWED=NO`,
    mac: `# Run native macOS menu bar app with ⌥ Space global hotkey:\n./scripts/run_mac.sh\n\n# Or build release archive locally:\n./scripts/release-mac.sh`
  };

  window.switchCliTab = function (tabKey) {
    document.querySelectorAll('.cli-tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tab === tabKey);
    });
    const cliCode = document.getElementById('cliCodeContent');
    if (cliCode && CLI_COMMANDS[tabKey]) {
      cliCode.textContent = CLI_COMMANDS[tabKey];
    }
  };

  window.copyCliCode = function () {
    const cliCode = document.getElementById('cliCodeContent');
    if (cliCode) {
      navigator.clipboard.writeText(cliCode.textContent).then(() => {
        showToast('Terminal command copied! ✓');
      });
    }
  };

  // ==========================================================================
  // 05. PLATFORM SCREENSHOTS SWITCHER
  // ==========================================================================
  window.switchPlatformGallery = function (platform) {
    document.querySelectorAll('.platform-tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.platform === platform);
    });
    const iphoneGallery = document.getElementById('iphoneGallery');
    const watchGallery = document.getElementById('watchGallery');
    if (iphoneGallery && watchGallery) {
      if (platform === 'iphone') {
        iphoneGallery.style.display = 'grid';
        watchGallery.style.display = 'none';
      } else {
        iphoneGallery.style.display = 'none';
        watchGallery.style.display = 'grid';
      }
    }
  };

  // ==========================================================================
  // 06. KEYBOARD SHORTCUTS (Geek Navigation)
  // ==========================================================================
  function initKeyboardShortcuts() {
    window.addEventListener('keydown', e => {
      // Don't trigger if user is typing in form field
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;
      
      // 'T' key -> Theme Toggle
      if (e.key === 't' || e.key === 'T') {
        toggleTheme();
      }
      
      // 'Space' key -> Play / Pause Audio Demo
      if (e.code === 'Space') {
        const demoSection = document.getElementById('demo');
        if (demoSection) {
          const rect = demoSection.getBoundingClientRect();
          // Only trigger if demo section is partly visible
          if (rect.top < window.innerHeight && rect.bottom > 0) {
            e.preventDefault();
            window.togglePlaySimulation();
          }
        }
      }
      
      // 'Escape' key -> Close mobile nav
      if (e.key === 'Escape') {
        const links = document.getElementById('navLinks');
        if (links && links.classList.contains('open')) {
          links.classList.remove('open');
          const toggle = document.getElementById('navToggle');
          if (toggle) toggle.setAttribute('aria-expanded', 'false');
        }
      }
    });
  }

  // ==========================================================================
  // 07. MOBILE NAVIGATION & SCROLL REVEAL
  // ==========================================================================
  function initMobileNav() {
    const toggle = document.getElementById('navToggle');
    const links = document.getElementById('navLinks');
    if (toggle && links) {
      toggle.addEventListener('click', () => {
        const isOpen = links.classList.toggle('open');
        toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      });

      links.querySelectorAll('a').forEach(a => {
        a.addEventListener('click', () => {
          links.classList.remove('open');
          toggle.setAttribute('aria-expanded', 'false');
        });
      });
    }
  }

  function initScrollReveal() {
    const revealEls = document.querySelectorAll('.reveal');
    if (revealEls.length && 'IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            entry.target.classList.add('in-view');
            observer.unobserve(entry.target);
          }
        });
      }, { threshold: 0.1 });
      revealEls.forEach(el => observer.observe(el));
    } else {
      revealEls.forEach(el => el.classList.add('in-view'));
    }
  }

  function initBackToTop() {
    const backBtn = document.querySelector('.back-to-top');
    if (backBtn) {
      window.addEventListener('scroll', () => {
        backBtn.classList.toggle('visible', window.scrollY > 400);
      }, { passive: true });
      backBtn.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }
  }

  function initThemeButtons() {
    document.querySelectorAll('.theme-toggle').forEach(btn => {
      btn.addEventListener('click', toggleTheme);
    });
  }

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================
  function init() {
    applyTheme(getStoredTheme());
    initThemeButtons();
    initMobileNav();
    initScrollReveal();
    initBackToTop();
    initWaveformScrubber();
    initKeyboardShortcuts();
    renderWorkbench();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
