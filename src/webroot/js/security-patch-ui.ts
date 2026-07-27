import { exec, getModuleDir } from './bridge.js';
import { getTranslation } from './i18n.js';
import { showToast, closeToast } from './toast.js';
import { API_URLS, defaultSecurityPatch } from './constants.js';
import { fetchJson, shellEscape } from './utils.js';
import type { KeystoreManagerJson } from './types.js';
const t = (key: string, fallback: string): string => getTranslation(key) || fallback;

function isOmkPatchValue(val: string): boolean {
  return val === 'auto' || val === 'latest' || /^\d{4}-\d{2}-\d{2}$/.test(val);
}

function isDatePatchValue(val: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(val);
}

export function wireSecurityPatch() {
  const btn = document.getElementById('security-patch-btn');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    const moddir = getModuleDir();
    if (!moddir) {
      showToast(t('simple_toast_error', 'Failed'), { icon: 'error', type: 'error', autoCloseDelay: 3000 });
      return;
    }
    const defaultDate = defaultSecurityPatch();
    const scriptPath = shellEscape(moddir + '/features/security_patch.sh');

    let isOmk = false;
    try {
      const km = await fetchJson<KeystoreManagerJson>(API_URLS.KEYSTORE_MANAGER!, 0);
      isOmk = km?.id === 'omk';
    } catch {
      isOmk = false;
    }

    let current = '';
    try {
      const { stdout } = await exec(`sh ${scriptPath} --get 2>/dev/null || echo ""`);
      current = stdout.trim();
    } catch {
      current = '';
    }

    const label = isOmk
      ? t('sp_dialog_label_omk', 'Security Patch')
      : t('sp_dialog_label', 'Security Patch Date');
    const placeholder = isOmk
      ? t('sp_placeholder_omk', 'auto, latest, or YYYY-MM-DD')
      : t('sp_placeholder', 'YYYY-MM-DD');

    const dialog = document.createElement('md-dialog');
    dialog.innerHTML = `
      <div slot="headline">${t('sp_dialog_title', 'Set Security Patch')}</div>
      <div slot="content" style="min-height:0">
        <md-outlined-text-field id="sp-input" type="text" label="${label}" placeholder="${placeholder}" maxlength="10" autocapitalize="none" ${isOmk ? `helper-text="${t('sp_helper_omk', 'auto, latest, or YYYY-MM-DD')}"` : ''} style="width:100%;--md-outlined-text-field-container-shape:14px;--md-outlined-field-with-trailing-content-trailing-space:24px;overflow:hidden">
          <div slot="trailing-icon" style="display:flex;align-items:center;gap:2px">
            <md-icon-button id="sp-device" style="--md-icon-button-icon-size:18px;width:32px;height:32px" aria-label="${t('sp_device', 'Device')}">
              <md-icon>smartphone</md-icon>
            </md-icon-button>
            <md-icon-button id="sp-fetch" style="--md-icon-button-icon-size:18px;width:32px;height:32px" aria-label="${t('sp_fetch', 'Fetch')}">
              <md-icon>language</md-icon>
            </md-icon-button>
          </div>
        </md-outlined-text-field>
      </div>
      <div slot="actions">
        <md-text-button id="sp-cancel">${t('dialog_cancel', 'Cancel')}</md-text-button>
        <md-filled-tonal-button id="sp-save">${t('dialog_save', 'Save')}</md-filled-tonal-button>
      </div>
    `;
    document.body.appendChild(dialog);

    const input = dialog.querySelector('#sp-input') as MdOutlinedTextField | null;
    if (input) {
      if (current && (isOmk ? isOmkPatchValue(current) : isDatePatchValue(current))) {
        input.value = current;
      } else {
        input.value = defaultDate;
      }
    }

    dialog.querySelector('#sp-device')!.addEventListener('click', async () => {
      const blockClose = (e: Event) => e.preventDefault();
      dialog.addEventListener('cancel', blockClose);
      try {
        try {
          const { stdout, code } = await exec(`sh ${scriptPath} --device 2>/dev/null`);
          const date = stdout.trim();
          if (code === 0 && date && isDatePatchValue(date)) {
            input!.value = date;
            showToast(t('sp_device_loaded', 'Loaded device security patch'), { icon: 'check_circle', type: 'success', autoCloseDelay: 2500 });
          } else {
            showToast(t('sp_device_unavailable', 'Device security patch unavailable'), { icon: 'error', type: 'error', autoCloseDelay: 3000 });
          }
        } catch {
          showToast(t('sp_device_unavailable', 'Device security patch unavailable'), { icon: 'error', type: 'error', autoCloseDelay: 3000 });
        }
      } finally {
        dialog.removeEventListener('cancel', blockClose);
      }
    });

    dialog.querySelector('#sp-fetch')!.addEventListener('click', async () => {
      const blockClose = (e: Event) => e.preventDefault();
      dialog.addEventListener('cancel', blockClose);
      try {
        const fetchingToast = showToast(t('sp_fetching', 'Fetching latest security patch...'), { icon: 'info', type: 'info', autoCloseDelay: 10000 });
        try {
          const { stdout } = await exec(`sh ${scriptPath} --fetch 2>/dev/null || echo ""`);
          closeToast(fetchingToast);
          const val = stdout.trim();
          const ok = isOmk ? isOmkPatchValue(val) : isDatePatchValue(val);
          if (ok) {
            input!.value = val;
            showToast(t('sp_fetched', 'Latest security patch fetched'), { icon: 'check_circle', type: 'success', autoCloseDelay: 2500 });
          } else {
            showToast(t('simple_toast_error', 'Failed'), { icon: 'error', type: 'error', autoCloseDelay: 3000 });
          }
        } catch {
          closeToast(fetchingToast);
          showToast(t('simple_toast_error', 'Failed'), { icon: 'error', type: 'error', autoCloseDelay: 3000 });
        }
      } finally {
        dialog.removeEventListener('cancel', blockClose);
      }
    });

    dialog.querySelector('#sp-cancel')!.addEventListener('click', () => dialog.close());
    dialog.querySelector('#sp-save')!.addEventListener('click', async () => {
      const blockClose = (e: Event) => e.preventDefault();
      dialog.addEventListener('cancel', blockClose);
      try {
        const val = input!.value.trim();
        const valid = isOmk ? isOmkPatchValue(val) : isDatePatchValue(val);
        if (!val || !valid) {
          showToast(
            isOmk
              ? t('sp_invalid_omk', 'Use auto, latest, or YYYY-MM-DD')
              : t('sp_invalid_date', 'Invalid date format (use YYYY-MM-DD)'),
            { icon: 'error', type: 'error', autoCloseDelay: 3000 },
          );
          return;
        }
        try {
          const { code, stderr } = await exec(`sh ${scriptPath} --set ${shellEscape(val)}`);
          if (code !== 0) {
            showToast(t('sp_save_error', stderr.trim() || 'Failed to save'), { icon: 'error', type: 'error', autoCloseDelay: 4000 });
            return;
          }
          await exec(`sh ${shellEscape(moddir + '/refresh_desc.sh')}`);
          showToast(t('sp_saved', 'Security patch date saved'), { icon: 'check_circle', type: 'success', autoCloseDelay: 2500 });
          dialog.close();
        } catch {
          showToast(t('sp_save_error', 'Failed to save'), { icon: 'error', type: 'error', autoCloseDelay: 4000 });
        }
      } finally {
        dialog.removeEventListener('cancel', blockClose);
      }
    });

    dialog.addEventListener('close', () => document.body.removeChild(dialog));
    dialog.show();
  });
}
