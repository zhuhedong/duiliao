(() => {
  const toast = (message) => {
    let el = document.querySelector('.prototype-toast');
    if (!el) {
      el = document.createElement('div');
      el.className = 'prototype-toast';
      el.style.cssText = 'position:fixed;left:50%;bottom:calc(var(--tabbar-h,72px) + 16px);transform:translate(-50%,8px);z-index:90;max-width:calc(100% - 32px);padding:9px 13px;border:1px solid var(--glass-border);border-radius:11px;background:var(--glass-bg-strong);color:var(--foreground-strong);box-shadow:0 12px 30px -16px #000;backdrop-filter:blur(18px);font-size:11px;opacity:0;pointer-events:none;transition:opacity .18s,transform .18s;text-align:center;';
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.style.opacity = '1';
    el.style.transform = 'translate(-50%,0)';
    clearTimeout(el._timer);
    el._timer = setTimeout(() => { el.style.opacity = '0'; el.style.transform = 'translate(-50%,8px)'; }, 1800);
  };
  const textOf = (node) => (node.textContent || '').replace(/\s+/g, ' ').trim();

  const normalizeButtons = (root = document) => {
    root.querySelectorAll('button:not([type])').forEach((button) => { button.type = 'button'; });
  };
  normalizeButtons();
  new MutationObserver((mutations) => {
    mutations.forEach((mutation) => mutation.addedNodes.forEach((node) => {
      if (node.nodeType !== 1) return;
      if (node.matches?.('button:not([type])')) node.type = 'button';
      normalizeButtons(node);
    }));
  }).observe(document.body, { childList: true, subtree: true });

  document.querySelectorAll('.switch').forEach((switchEl) => {
    switchEl.setAttribute('role', 'switch');
    switchEl.setAttribute('tabindex', '0');
    switchEl.setAttribute('aria-checked', switchEl.classList.contains('on') ? 'true' : 'false');
  });
  document.querySelectorAll('.segmented').forEach((group) => {
    group.querySelectorAll('button').forEach((button) => button.setAttribute('aria-pressed', button.classList.contains('seg-on') ? 'true' : 'false'));
  });

  const loginForm = document.querySelector('#loginForm');
  if (loginForm) {
    loginForm.addEventListener('submit', (event) => {
      event.preventDefault();
      const account = loginForm.querySelector('[name="account"]');
      const password = loginForm.querySelector('[name="password"]');
      if (!account.value.trim() || !password.value) {
        toast('请填写账号和密码');
        (account.value.trim() ? password : account).focus();
        return;
      }
      toast('演示原型：未连接身份服务，未登录');
    });
    const toggle = loginForm.querySelector('.password-toggle');
    if (toggle) toggle.addEventListener('click', () => {
      const password = loginForm.querySelector('[name="password"]');
      const visible = password.type === 'text';
      password.type = visible ? 'password' : 'text';
      toggle.setAttribute('aria-label', visible ? '显示密码' : '隐藏密码');
    });
  }

  const passwordForm = document.querySelector('#passwordForm');
  if (passwordForm) {
    passwordForm.addEventListener('submit', (event) => {
      event.preventDefault();
      const current = passwordForm.querySelector('[name="currentPassword"]');
      const next = passwordForm.querySelector('[name="newPassword"]');
      const confirm = passwordForm.querySelector('[name="confirmPassword"]');
      if (!current.value || !next.value || !confirm.value) {
        toast('请完整填写当前密码和新密码');
        (!current.value ? current : !next.value ? next : confirm).focus();
        return;
      }
      if (next.value.length < 8) {
        toast('新密码至少需要 8 位');
        next.focus();
        return;
      }
      if (next.value !== confirm.value) {
        toast('两次输入的新密码不一致');
        confirm.focus();
        return;
      }
      toast('演示原型：未连接账号服务，未修改密码');
    });
  }

  const aiButton = document.querySelector('a[href="ai-report.html"]');
  if (aiButton && /开始研判/.test(textOf(aiButton))) {
    aiButton.addEventListener('click', (event) => {
      const prompt = document.querySelector('input[placeholder*="研判指令"]');
      if (!prompt || !prompt.value.trim()) {
        event.preventDefault();
        toast('请先输入研判指令；当前为演示原型，未连接 AI 服务');
      }
    });
  }

  document.addEventListener('keydown', (event) => {
    const switchEl = event.target.closest('.switch');
    if (switchEl && (event.key === ' ' || event.key === 'Enter')) {
      event.preventDefault();
      switchEl.click();
    }
  });

  document.addEventListener('click', (event) => {
    const switchEl = event.target.closest('.switch');
    if (switchEl) {
      switchEl.classList.toggle('on');
      switchEl.setAttribute('aria-checked', switchEl.classList.contains('on') ? 'true' : 'false');
      return;
    }

    const tabButton = event.target.closest('.segmented button');
    if (tabButton) {
      const group = tabButton.parentElement;
      group.querySelectorAll('button').forEach((button) => {
        const active = button === tabButton;
        button.classList.toggle('seg-on', active);
        button.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
      return;
    }

    const emptyLink = event.target.closest('a[href="#"]');
    const saveLink = event.target.closest('a[href="records.html"]');
    if (emptyLink || (saveLink && /保存记录/.test(textOf(saveLink)))) {
      event.preventDefault();
      const label = textOf(emptyLink || saveLink) || '此操作';
      if (/导出|复制/.test(label)) toast(`${label}：原型演示已触发`);
      else if (/保存|确认|检测|巡检|同步|触发|查询|计算|清理|补齐|初始化|忘记/.test(label)) toast(`${label}：已提交演示操作`);
      else toast(`${label}：当前为原型演示入口`);
      return;
    }

    const demoButton = event.target.closest('button');
    if (demoButton && !demoButton.closest('.segmented') && !demoButton.closest('.switch') && !demoButton.matches('.password-toggle, .filter-chip, [data-mode], #clearFilters, #clearResult, #copyResult, .consensus-selectable, .board-tabs button, .period-chip')) {
      if (demoButton.type !== 'submit') toast(`${textOf(demoButton) || '此操作'}：当前为原型演示入口`);
    }
  });

  document.querySelectorAll('input[placeholder*="筛选"], input[placeholder*="来源名称"]').forEach((input) => {
    input.addEventListener('input', () => {
      const query = input.value.trim().toLowerCase();
      const scope = input.closest('.glass-card, section') || document;
      scope.querySelectorAll('.list-item, .audit-row').forEach((row) => {
        row.style.display = !query || textOf(row).toLowerCase().includes(query) ? '' : 'none';
      });
    });
  });
})();
