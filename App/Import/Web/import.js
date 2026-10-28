// The QR import page. Reads the session key from the URL fragment, seals
// the name and config with tweetnacl-js's secretbox, and posts the result
// to the TV. Nothing here talks to anything but the TV that served it.
//
// Plain ES5 with no browser-only APIs in the sealing code, so the app's
// tests can run `UntetheredImport.seal` in JavaScriptCore.
(function (root) {
  'use strict';

  // The TV refuses bodies over 16 KB; base64 grows the sealed bytes by 4/3.
  var MAX_BODY = 16 * 1024;

  function utf8(text) {
    var binary = unescape(encodeURIComponent(text));
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  var ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function base64(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
      out += ALPHABET[(n >> 18) & 63] + ALPHABET[(n >> 12) & 63];
      out += i + 1 < bytes.length ? ALPHABET[(n >> 6) & 63] : '=';
      out += i + 2 < bytes.length ? ALPHABET[n & 63] : '=';
    }
    return out;
  }

  // Base64url without padding, as the TV writes the key. Null unless it is
  // exactly 32 bytes.
  function keyFromFragment(text) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(text)) return null;
    var standard = text.replace(/-/g, '+').replace(/_/g, '/');
    var bits = 0, value = 0, bytes = [];
    for (var i = 0; i < standard.length; i++) {
      value = (value << 6) | ALPHABET.indexOf(standard[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.push((value >> bits) & 255);
      }
    }
    return bytes.length === 32 ? new Uint8Array(bytes) : null;
  }

  // {"name","config"} as JSON, sealed (nonce then box), in base64.
  function seal(name, config, key) {
    var message = utf8(JSON.stringify({ name: name, config: config }));
    var nonce = root.nacl.randomBytes(root.nacl.secretbox.nonceLength);
    var box = root.nacl.secretbox(message, nonce, key);
    var sealed = new Uint8Array(nonce.length + box.length);
    sealed.set(nonce);
    sealed.set(box, nonce.length);
    return base64(sealed);
  }

  root.UntetheredImport = { seal: seal, keyFromFragment: keyFromFragment, MAX_BODY: MAX_BODY };

  if (typeof document === 'undefined') return;

  // ---- The page ----

  var key = keyFromFragment(location.hash.slice(1));
  // Keep the key out of the browser's history and out of anything shared
  // from this tab. A reload then needs a fresh scan, which is fine.
  if (history.replaceState) history.replaceState(null, '', location.pathname);

  var form = document.getElementById('form');
  var nameField = document.getElementById('name');
  var configField = document.getElementById('config');
  var fileInput = document.getElementById('file');
  var sendButton = document.getElementById('send');
  var status = document.getElementById('status');

  if (!key) {
    document.getElementById('link-problem').hidden = false;
    form.hidden = true;
    return;
  }

  function show(text, kind) {
    status.textContent = text;
    status.className = 'message' + (kind ? ' ' + kind : '');
    status.hidden = false;
  }

  // The file input has no accept list: iOS has no file type for .conf and
  // would grey those files out, so any file can be picked and checked here.
  fileInput.addEventListener('change', function () {
    var file = fileInput.files && fileInput.files[0];
    fileInput.value = '';
    if (!file) return;
    if (file.size > 12 * 1024) {
      show('That file is too large to be a WireGuard config. Choose the .conf file.', 'error');
      return;
    }
    var reader = new FileReader();
    reader.onload = function () {
      var text = String(reader.result);
      if (!/^\s*\[Interface\]/im.test(text)) {
        show('That file doesn\u2019t look like a WireGuard config. Choose the .conf file, which starts with [Interface].', 'error');
        return;
      }
      configField.value = text;
      status.hidden = true;
    };
    reader.onerror = function () { show('That file couldn’t be read. Try pasting the config instead.', 'error'); };
    reader.readAsText(file);
  });

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    var name = nameField.value.trim();
    var config = configField.value;
    if (!name) { show('Enter a name, such as Home.', 'error'); nameField.focus(); return; }
    if (!config.trim()) { show('Paste your WireGuard config or choose its file.', 'error'); configField.focus(); return; }

    var body = seal(name, config, key);
    if (body.length > MAX_BODY) { show('This config is too large for the TV to accept.', 'error'); return; }

    sendButton.disabled = true;
    show('Sending…');
    fetch(location.pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: body,
      cache: 'no-store',
      credentials: 'omit',
      referrerPolicy: 'no-referrer'
    }).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (reply) {
        if (response.ok && reply.ok) {
          show('Sent. Now check the settings on your TV and choose Save.', 'success');
          form.querySelectorAll('input, textarea, button').forEach(function (el) {
            el.disabled = true;
          });
          form.querySelector('.file-row').hidden = true;
          configField.value = '';
        } else {
          show(reply.error || 'The TV didn’t accept this. Scan the code on the TV again.', 'error');
          sendButton.disabled = false;
        }
      });
    }).catch(function () {
      show('The TV didn’t answer. If the code on the TV has gone, scan the new one. Your phone must be on the same network as the TV.', 'error');
      sendButton.disabled = false;
    });
  });
})(this);
