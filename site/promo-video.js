// Promo videos (video[data-promo]) play only while they are on screen, and
// never start on their own for people who asked for reduced motion - the
// native controls still work. A pause the viewer made sticks: scrolling the
// video back into view does not restart it.
(() => {
  const videos = document.querySelectorAll('video[data-promo]');
  if (!videos.length || !('IntersectionObserver' in window)) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const v = e.target;
      if (e.isIntersecting) {
        if (!reduce.matches && !v.dataset.userPaused) v.play().catch(() => {});
      } else if (!v.paused) {
        v.dataset.autoPause = '1';
        v.pause();
      }
    }
  }, { threshold: 0.35 });
  videos.forEach((v) => {
    v.addEventListener('pause', () => {
      if (v.dataset.autoPause) delete v.dataset.autoPause;
      else v.dataset.userPaused = '1';
    });
    v.addEventListener('play', () => { delete v.dataset.userPaused; });
    io.observe(v);
  });
})();
