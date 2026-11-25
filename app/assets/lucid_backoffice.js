document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll("[data-lb-reason-form]").forEach(function (form) {
    var reason = form.querySelector("[data-lb-reason]");
    var submit = form.querySelector("[data-lb-submit]");
    var minimum = parseInt(reason.getAttribute("minlength"), 10) || 0;
    var sync = function () { submit.disabled = reason.value.trim().length < minimum; };
    reason.addEventListener("input", sync);
    reason.addEventListener("blur", sync);
    sync();
  });
});

document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll("[data-lb-action-form]").forEach(function (form) {
    var reason = form.querySelector("[data-lb-reason]");
    var submits = form.querySelectorAll("[data-lb-submit]");
    var confirmation = form.querySelector("[data-lb-confirmation]");
    if (!reason || submits.length === 0) { return; }
    var minimum = parseInt(reason.getAttribute("minlength"), 10) || 0;
    var expected = form.getAttribute("data-lb-expected");
    var sync = function () {
      var ok = reason.value.trim().length >= minimum;
      if (confirmation) { ok = ok && confirmation.value === expected; }
      submits.forEach(function (submit) { submit.disabled = !ok; });
    };
    reason.addEventListener("input", sync);
    if (confirmation) { confirmation.addEventListener("input", sync); }
    sync();
  });
});

document.addEventListener("DOMContentLoaded", function () {
  var toggle = document.querySelector(".lb-sidebar-toggle");
  if (toggle && window.matchMedia("(min-width: 40.01rem)").matches) { toggle.setAttribute("open", ""); }
});

document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll("[data-lb-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      var input = document.getElementById(button.getAttribute("data-lb-copy"));
      if (!input) { return; }
      input.select();
      if (navigator.clipboard) { navigator.clipboard.writeText(input.value); } else { document.execCommand("copy"); }
      button.textContent = button.getAttribute("data-lb-copied");
    });
  });
});

function lbDirty(root) {
  var fields = root.querySelectorAll("form:not(.lb-reveal-form) input, form:not(.lb-reveal-form) textarea, form:not(.lb-reveal-form) select");
  return Array.prototype.some.call(fields, function (field) {
    if (field.closest(".lb-reveal-form")) { return false; }
    var type = (field.getAttribute("type") || "").toLowerCase();
    if (type === "hidden" || type === "submit" || type === "button") { return false; }
    if (field.tagName === "SELECT") {
      return Array.prototype.some.call(field.options, function (option) { return option.selected !== option.defaultSelected; });
    }
    if (type === "checkbox" || type === "radio") { return field.checked !== field.defaultChecked; }
    return field.value !== field.defaultValue;
  });
}

document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll("[data-lb-countdown]").forEach(function (eye) {
    var label = eye.querySelector("[data-lb-countdown-label]");
    var form = eye.closest("form");
    var deadline = performance.now() + parseInt(eye.getAttribute("data-lb-remaining"), 10) * 1000;
    var running = eye.getAttribute("data-lb-label-running");
    var timer = null;
    var pad = function (n) { return n < 10 ? "0" + n : String(n); };
    var tick = function () {
      var left = Math.max(0, Math.ceil((deadline - performance.now()) / 1000));
      label.textContent = running.replace("%{time}", pad(Math.floor(left / 60)) + ":" + pad(left % 60));
      eye.classList.toggle("lb-eye-warn", left <= 60);
      if (left > 0) { return; }
      clearInterval(timer);
      if (!lbDirty(document)) { form.requestSubmit(); return; }
      document.documentElement.classList.add("lb-expired");
      eye.classList.remove("lb-eye-on", "lb-eye-warn");
      eye.classList.add("lb-eye-expired");
      label.textContent = eye.getAttribute("data-lb-label-expired");
      var end = eye.querySelector(".lb-eye-end");
      if (end) { end.hidden = true; }
    };
    timer = setInterval(tick, 1000);
    document.addEventListener("visibilitychange", function () { if (!document.hidden) { tick(); } });
    tick();
  });
});

document.addEventListener("DOMContentLoaded", function () {
  var eye = '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>';
  document.querySelectorAll("[data-lb-unlock]").forEach(function (box) {
    var button = box.querySelector("[data-lb-unlock-button]");
    var template = box.querySelector("template[data-lb-control]");
    var field = box.getAttribute("data-lb-field");
    var label = button.querySelector("[data-lb-label]");
    var icon = button.querySelector("svg");
    var control = null;
    var failure = null;

    var conceal = function (on) {
      box.classList.toggle("lb-concealed", on);
      label.textContent = button.getAttribute(on ? "data-lb-show" : "data-lb-hide");
    };

    var open = function (value) {
      var fragment = template.content.cloneNode(true);
      control = fragment.querySelector("input, textarea, select");
      if (value !== null && value !== undefined) {
        if (control.type === "checkbox") { control.checked = !!value; } else { control.value = value; }
      }
      box.replaceChild(fragment, box.querySelector("input:disabled"));
      var flag = document.createElement("input");
      flag.type = "hidden"; flag.name = "unlocked[]"; flag.value = field;
      box.appendChild(flag);
      icon.innerHTML = eye;
      button.onclick = function () { conceal(!box.classList.contains("lb-concealed")); if (!box.classList.contains("lb-concealed")) { control.focus(); } };
      box.addEventListener("focusout", function (event) {
        if (!box.contains(event.relatedTarget)) { conceal(true); }
      });
      conceal(false);
      control.focus();
    };

    button.onclick = function () {
      if (failure) { failure.remove(); failure = null; }
      var url = box.getAttribute("data-lb-unlock-url");
      if (!url) { open(""); return; }
      var token = document.querySelector('meta[name="csrf-token"]');
      button.disabled = true;
      fetch(url, { method: "POST", credentials: "same-origin", headers: { "Accept": "application/json", "X-CSRF-Token": token ? token.content : "" } })
        .then(function (response) { if (!response.ok) { throw new Error(response.status); } return response.json(); })
        .then(function (data) { open(data.value); })
        .catch(function () {
          failure = document.createElement("small");
          failure.className = "lb-unlock-failed";
          failure.textContent = button.getAttribute("data-lb-failed");
          box.appendChild(failure);
        })
        .finally(function () { button.disabled = false; });
    };
  });
});
