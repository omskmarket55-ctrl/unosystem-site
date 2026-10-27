// Uno System — главная: появление блоков при прокрутке и подсветка плиток под курсором.
(() => {
  const items = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add('is-in');
        io.unobserve(e.target);
      }
    }, { rootMargin: '0px 0px -8% 0px' });
    items.forEach((el) => io.observe(el));
  } else {
    items.forEach((el) => el.classList.add('is-in'));
  }

  // Пятно света следует за курсором внутри плитки
  for (const tile of document.querySelectorAll('a.tile')) {
    tile.addEventListener('pointermove', (e) => {
      const r = tile.getBoundingClientRect();
      tile.style.setProperty('--x', `${Math.round(e.clientX - r.left)}px`);
      tile.style.setProperty('--y', `${Math.round(e.clientY - r.top)}px`);
    });
  }
})();
