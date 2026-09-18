(function () {
  // Mobile nav toggle
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

  // Scroll-triggered reveal animations
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
        { threshold: 0.15, rootMargin: '0px 0px -60px 0px' }
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

  // Scroll-spy active state for in-page nav links
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

  // Back-to-top button
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
})();
