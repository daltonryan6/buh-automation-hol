document.addEventListener('DOMContentLoaded', () => {
  const steps = document.querySelectorAll('.step');
  const navItems = document.querySelectorAll('.nav-item');
  const progressText = document.querySelector('.progress-text');
  const themeBtn = document.querySelector('.theme-toggle');
  const menuBtn = document.querySelector('.menu-toggle');
  const sidebar = document.querySelector('.sidebar');

  let currentStep = 0;

  function showStep(idx) {
    if (idx < 0 || idx >= steps.length) return;
    steps.forEach(s => s.classList.remove('active'));
    navItems.forEach(n => n.classList.remove('active'));
    steps[idx].classList.add('active');
    navItems[idx].classList.add('active');
    currentStep = idx;
    progressText.textContent = 'Step ' + (idx + 1) + ' of ' + steps.length;
    window.scrollTo({ top: 0, behavior: 'smooth' });
    if (window.innerWidth <= 900) sidebar.classList.remove('open');
  }

  navItems.forEach((item, i) => {
    item.addEventListener('click', () => showStep(i));
  });

  document.querySelectorAll('.nav-btn-prev').forEach(btn => {
    btn.addEventListener('click', () => showStep(currentStep - 1));
  });

  document.querySelectorAll('.nav-btn-next').forEach(btn => {
    btn.addEventListener('click', () => showStep(currentStep + 1));
  });

  // Copy buttons
  document.querySelectorAll('.copy-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.closest('.code-block').querySelector('pre').textContent;
      navigator.clipboard.writeText(code).then(() => {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => {
          btn.textContent = 'Copy';
          btn.classList.remove('copied');
        }, 2000);
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

  // Mobile menu
  if (menuBtn) {
    menuBtn.addEventListener('click', () => sidebar.classList.toggle('open'));
  }

  // Keyboard nav
  document.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
      e.preventDefault();
      showStep(currentStep + 1);
    }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      e.preventDefault();
      showStep(currentStep - 1);
    }
  });

  showStep(0);
});
