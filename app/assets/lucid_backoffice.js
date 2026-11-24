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
