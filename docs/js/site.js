(function () {
  'use strict';

  // ==========================================================================
  // Theme Management (Light / Dark with System Preference & LocalStorage)
  // ==========================================================================
  var THEME_STORAGE_KEY = 'voxbrief-theme';

  function getSystemTheme() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches
      ? 'light'
      : 'dark';
  }

  function getSavedTheme() {
    try {
      var saved = localStorage.getItem(THEME_STORAGE_KEY);
      if (saved === 'light' || saved === 'dark') {
        return saved;
      }
    } catch (e) {
      console.warn('LocalStorage unavailable for theme storage:', e);
    }
    return getSystemTheme();
  }

  function updateThemeUI(theme) {
    document.documentElement.setAttribute('data-theme', theme);

    // Update meta theme-color for iOS Safari and mobile chrome status bar
    var metaTheme = document.querySelector('meta[name="theme-color"]');
    if (metaTheme) {
      metaTheme.setAttribute('content', theme === 'light' ? '#f8fafc' : '#050811');
    }

    // Update accessible labels on all theme toggle buttons
    var toggles = document.querySelectorAll('.theme-toggle');
    toggles.forEach(function (btn) {
      var nextTheme = theme === 'light' ? 'dark' : 'light';
      btn.setAttribute('aria-label', 'Switch to ' + nextTheme + ' theme');
      btn.setAttribute('title', 'Switch to ' + nextTheme + ' theme');
      btn.setAttribute('aria-pressed', theme === 'light' ? 'true' : 'false');
    });
  }

  function setTheme(theme) {
    try {
      localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch (e) {
      console.warn('LocalStorage write failed:', e);
    }
    updateThemeUI(theme);
  }

  // Initialize theme immediately
  var activeTheme = getSavedTheme();
  updateThemeUI(activeTheme);

  // Setup theme toggle buttons on DOM ready
  function initThemeToggles() {
    var toggles = document.querySelectorAll('.theme-toggle');
    toggles.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var current = document.documentElement.getAttribute('data-theme') || activeTheme;
        var next = current === 'light' ? 'dark' : 'light';
        setTheme(next);
      });
    });
  }

  // React to OS-level dark/light mode preference change if no explicit choice stored
  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function (e) {
      try {
        if (!localStorage.getItem(THEME_STORAGE_KEY)) {
          updateThemeUI(e.matches ? 'light' : 'dark');
        }
      } catch (err) {}
    });
  }

  // ==========================================================================
  // Mobile Navigation
  // ==========================================================================
  function initMobileNav() {
    var toggle = document.querySelector('.nav-toggle');
    var links = document.getElementById('navLinks');
    if (toggle && links) {
      toggle.addEventListener('click', function () {
        var isOpen = links.classList.toggle('open');
        toggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      });

      links.querySelectorAll('a').forEach(function (a) {
        a.addEventListener('click', function () {
          links.classList.remove('open');
          toggle.setAttribute('aria-expanded', 'false');
        });
      });

      document.addEventListener('click', function (evt) {
        if (!links.classList.contains('open')) return;
        if (links.contains(evt.target) || toggle.contains(evt.target)) return;
        links.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    }
  }

  // ==========================================================================
  // Scroll-Triggered Reveal Animations
  // ==========================================================================
  function initScrollReveal() {
    var revealEls = document.querySelectorAll('.reveal');
    if (revealEls.length) {
      if ('IntersectionObserver' in window) {
        var observer = new IntersectionObserver(
          function (entries) {
            entries.forEach(function (entry) {
              if (entry.isIntersecting) {
                entry.target.classList.add('in-view');
                observer.unobserve(entry.target);
              }
            });
          },
          { threshold: 0.12, rootMargin: '0px 0px -50px 0px' }
        );
        revealEls.forEach(function (el) {
          observer.observe(el);
        });
      } else {
        revealEls.forEach(function (el) {
          el.classList.add('in-view');
        });
      }
    }
  }

  // ==========================================================================
  // In-Page Scroll-Spy Navigation Active State
  // ==========================================================================
  function initScrollSpy() {
    var sectionLinks = Array.prototype.slice.call(
      document.querySelectorAll('.nav-links a[href^="#"]')
    );
    if (sectionLinks.length && 'IntersectionObserver' in window) {
      var sections = sectionLinks
        .map(function (a) {
          return document.querySelector(a.getAttribute('href'));
        })
        .filter(Boolean);

      var spy = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            var link = document.querySelector(
              '.nav-links a[href="#' + entry.target.id + '"]'
            );
            if (!link || !entry.isIntersecting) return;
            sectionLinks.forEach(function (a) {
              a.classList.remove('active');
            });
            link.classList.add('active');
          });
        },
        { rootMargin: '-45% 0px -50% 0px' }
      );
      sections.forEach(function (s) {
        spy.observe(s);
      });
    }
  }

  // ==========================================================================
  // Back-to-Top Button
  // ==========================================================================
  function initBackToTop() {
    var backToTop = document.querySelector('.back-to-top');
    if (backToTop) {
      window.addEventListener(
        'scroll',
        function () {
          backToTop.classList.toggle('visible', window.scrollY > 480);
        },
        { passive: true }
      );
      backToTop.addEventListener('click', function () {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }
  }

  // Initialize all interactive components when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      initThemeToggles();
      initMobileNav();
      initScrollReveal();
      initScrollSpy();
      initBackToTop();
    });
  } else {
    initThemeToggles();
    initMobileNav();
    initScrollReveal();
    initScrollSpy();
    initBackToTop();
  }
})();
