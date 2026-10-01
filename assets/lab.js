document.addEventListener('DOMContentLoaded', () => {
  const steps = document.querySelectorAll('.step');
  const navItems = document.querySelectorAll('.nav-item');
  const flowCards = document.querySelectorAll('.flow-card');
  const themeBtn = document.querySelector('.theme-toggle');
  let currentStep = 0;

  function showStep(idx) {
    if (idx < 0 || idx >= steps.length) return;
    steps.forEach(s => s.classList.remove('active'));
    navItems.forEach(n => n.classList.remove('active'));
    flowCards.forEach(c => c.classList.remove('active'));
    steps[idx].classList.add('active');
    if (navItems[idx]) navItems[idx].classList.add('active');
    if (flowCards[idx]) flowCards[idx].classList.add('active');
    currentStep = idx;
    window.scrollTo({ top: document.querySelector('.docs-content').offsetTop - 20, behavior: 'smooth' });
  }

  navItems.forEach((item, i) => item.addEventListener('click', () => showStep(i)));
  flowCards.forEach((card, i) => card.addEventListener('click', () => showStep(i)));

  document.querySelectorAll('.nav-btn-prev').forEach(btn =>
    btn.addEventListener('click', () => showStep(currentStep - 1)));
  document.querySelectorAll('.nav-btn-next').forEach(btn =>
    btn.addEventListener('click', () => showStep(currentStep + 1)));

  // Copy buttons
  document.querySelectorAll('.copy-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.closest('.code-block').querySelector('pre').textContent;
      navigator.clipboard.writeText(code).then(() => {
        const orig = btn.textContent;
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = orig; btn.classList.remove('copied'); }, 2000);
      });
    });
  });

  // Theme toggle
  if (themeBtn) {
    const saved = localStorage.getItem('buh-lab-theme');
    if (saved === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
    themeBtn.addEventListener('click', () => {
      const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
      if (isDark) {
        document.documentElement.removeAttribute('data-theme');
        localStorage.setItem('buh-lab-theme', 'light');
      } else {
        document.documentElement.setAttribute('data-theme', 'dark');
        localStorage.setItem('buh-lab-theme', 'dark');
      }
    });
  }

  // Keyboard nav
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.key === 'ArrowRight') { e.preventDefault(); showStep(currentStep + 1); }
    if (e.key === 'ArrowLeft') { e.preventDefault(); showStep(currentStep - 1); }
  });

  showStep(0);
});
